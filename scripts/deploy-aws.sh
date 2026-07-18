#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="${PROJECT_NAME:-devops-starter-kit}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"

required_commands=(aws docker terraform kubectl jq)
for command_name in "${required_commands[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

echo "[1/7] Provisioning AWS infrastructure with Terraform"
terraform -chdir="$ROOT_DIR/terraform" init
terraform -chdir="$ROOT_DIR/terraform" apply -auto-approve \
  -var="project_name=$PROJECT_NAME" \
  -var="aws_region=$AWS_REGION"

CLUSTER_NAME="$(terraform -chdir="$ROOT_DIR/terraform" output -raw cluster_name)"
ECR_URL="$(terraform -chdir="$ROOT_DIR/terraform" output -raw ecr_repository_url)"
SECRET_NAME="$(terraform -chdir="$ROOT_DIR/terraform" output -raw database_secret_name)"
IMAGE_URI="${ECR_URL}:${IMAGE_TAG}"
ECR_REGISTRY="${ECR_URL%%/*}"

echo "[2/7] Logging Docker in to Amazon ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "[3/7] Building the application image"
docker build \
  --build-arg "APP_VERSION=$IMAGE_TAG" \
  --build-arg "GIT_COMMIT=$IMAGE_TAG" \
  --tag "$IMAGE_URI" \
  "$ROOT_DIR"

echo "[4/7] Pushing the image to Amazon ECR"
docker push "$IMAGE_URI"

echo "[5/7] Connecting kubectl to Amazon EKS"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

SECRET_JSON="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_NAME" \
  --query SecretString \
  --output text)"
DATABASE_URL="$(printf '%s' "$SECRET_JSON" | jq -r '.DATABASE_URL')"

echo "[6/7] Applying Kubernetes resources"
kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"
kubectl apply -f "$ROOT_DIR/k8s/configmap.yaml"
kubectl -n devops-starter-kit create secret generic database-secret \
  --from-literal="DATABASE_URL=$DATABASE_URL" \
  --dry-run=client -o yaml | kubectl apply -f -
sed "s|IMAGE_URI|$IMAGE_URI|g" "$ROOT_DIR/k8s/deployment.yaml" | kubectl apply -f -
kubectl apply -f "$ROOT_DIR/k8s/service.yaml"
kubectl apply -f "$ROOT_DIR/k8s/pod-disruption-budget.yaml"
kubectl -n devops-starter-kit rollout status deployment/devops-starter-kit-app --timeout=10m

echo "[7/7] Deployment complete"
LOAD_BALANCER=""
for _ in {1..60}; do
  LOAD_BALANCER="$(kubectl -n devops-starter-kit get service devops-starter-kit-service \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [[ -n "$LOAD_BALANCER" ]] && break
  sleep 5
done

kubectl -n devops-starter-kit get pods,service
if [[ -n "$LOAD_BALANCER" ]]; then
  echo "Application URL: http://$LOAD_BALANCER"
else
  echo "The service is deployed. Run 'kubectl -n devops-starter-kit get service' until the hostname appears."
fi
