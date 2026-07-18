#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="${PROJECT_NAME:-devops-starter-kit}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
CLUSTER_NAME="${PROJECT_NAME}-eks"

if aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
  kubectl -n devops-starter-kit delete service devops-starter-kit-service \
    --ignore-not-found --wait=true --timeout=10m || true
  kubectl delete namespace devops-starter-kit --ignore-not-found --wait=true --timeout=5m || true
fi

terraform -chdir="$ROOT_DIR/terraform" init
terraform -chdir="$ROOT_DIR/terraform" destroy -auto-approve \
  -var="project_name=$PROJECT_NAME" \
  -var="aws_region=$AWS_REGION"
