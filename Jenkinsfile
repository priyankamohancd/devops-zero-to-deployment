pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    timeout(time: 90, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  parameters {
    booleanParam(
      name: 'APPLY_INFRA',
      defaultValue: false,
      description: 'Create or update VPC, ECR, EKS, RDS and IAM resources using Terraform.'
    )

    booleanParam(
      name: 'DEPLOY_TO_AWS',
      defaultValue: false,
      description: 'Build, push the Docker image to Amazon ECR and deploy it to Amazon EKS.'
    )

    string(
      name: 'AWS_REGION',
      defaultValue: 'eu-central-1',
      description: 'AWS region used by Terraform, ECR and EKS.'
    )

    string(
      name: 'PROJECT_NAME',
      defaultValue: 'devops-zero-to-deployment',
      description: 'Prefix used for AWS resources and Docker images.'
    )
  }

  environment {
    PYTHONUNBUFFERED = '1'

    /*
     * These values must exactly match the names used
     * inside the Kubernetes YAML files.
     */
    K8S_NAMESPACE  = 'devops-starter-kit'
    K8S_DEPLOYMENT = 'devops-starter-kit-app'
    K8S_SERVICE    = 'devops-starter-kit-service'
    K8S_INGRESS    = 'devops-starter-kit-ingress'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm

        script {
          def selectedProject = params.PROJECT_NAME?.trim()
          def selectedRegion = params.AWS_REGION?.trim()

          env.PROJECT_NAME =
            selectedProject ?: 'devops-zero-to-deployment'

          env.AWS_REGION =
            selectedRegion ?: 'eu-central-1'

          env.AWS_DEFAULT_REGION = env.AWS_REGION

          env.GIT_SHORT = sh(
            script: 'git rev-parse --short HEAD',
            returnStdout: true
          ).trim()

          env.IMAGE_TAG =
            "${env.BUILD_NUMBER}-${env.GIT_SHORT}"

          env.LOCAL_IMAGE =
            "${env.PROJECT_NAME}-app:${env.IMAGE_TAG}"

          env.APPLY_INFRA_EFFECTIVE =
            params.APPLY_INFRA.toString()

          env.DEPLOY_TO_AWS_EFFECTIVE =
            params.DEPLOY_TO_AWS.toString()

          echo "Project name: ${env.PROJECT_NAME}"
          echo "AWS region: ${env.AWS_REGION}"
          echo "Git commit: ${env.GIT_SHORT}"
          echo "Image tag: ${env.IMAGE_TAG}"
          echo "Local image: ${env.LOCAL_IMAGE}"
          echo "Apply infrastructure: ${env.APPLY_INFRA_EFFECTIVE}"
          echo "Deploy application: ${env.DEPLOY_TO_AWS_EFFECTIVE}"
        }
      }
    }

    stage('Lint and Unit Test') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

rm -rf .venv

python3 -m venv .venv
. .venv/bin/activate

python -m pip install --upgrade pip

pip install \
  -r app/requirements.txt \
  flake8 \
  pytest

flake8 app/ \
  --max-line-length=100 \
  --exclude=.venv,__pycache__

cd app

pytest \
  -v \
  --tb=short \
  --junitxml=junit.xml
'''
      }
    }

    stage('Validate Terraform') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

terraform -chdir=terraform init \
  -backend=false \
  -input=false

terraform -chdir=terraform fmt \
  -check \
  -recursive \
  -diff

terraform -chdir=terraform validate
'''
      }
    }

    stage('Build Docker Image') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

echo "Jenkins machine architecture:"
uname -m

export DOCKER_BUILDKIT=1

echo "Building linux/amd64 image for the EKS t3 worker node..."

docker build \
  --platform linux/amd64 \
  --build-arg "APP_VERSION=${IMAGE_TAG}" \
  --build-arg "GIT_COMMIT=${GIT_SHORT}" \
  --tag "${LOCAL_IMAGE}" \
  .

IMAGE_ARCH=$(docker image inspect \
  "${LOCAL_IMAGE}" \
  --format '{{.Architecture}}')

echo "Docker image architecture: ${IMAGE_ARCH}"

if [ "${IMAGE_ARCH}" != "amd64" ]; then
  echo "ERROR: Expected amd64, but Docker built ${IMAGE_ARCH}."
  exit 1
fi

echo "Docker image created successfully:"
docker image ls "${LOCAL_IMAGE}"
'''
      }
    }

    stage('Security Scan') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image \
  --no-progress \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  "${LOCAL_IMAGE}"
'''
      }
    }

    stage('Check AWS Access') {
      when {
        expression {
          return params.APPLY_INFRA == true ||
                 params.DEPLOY_TO_AWS == true
        }
      }

      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          sh '''#!/usr/bin/env bash
set -euo pipefail

echo "AWS identity used by Jenkins:"
aws sts get-caller-identity

if [ "${APPLY_INFRA_EFFECTIVE}" = "true" ]; then
  echo "Testing EC2 Availability Zone access..."

  aws ec2 describe-availability-zones \
    --region "${AWS_REGION}" \
    --query 'AvailabilityZones[?State==`available`].ZoneName' \
    --output table
fi

if [ "${DEPLOY_TO_AWS_EFFECTIVE}" = "true" ] &&
   [ "${APPLY_INFRA_EFFECTIVE}" = "false" ]; then

  echo "Checking existing EKS cluster..."

  aws eks describe-cluster \
    --region "${AWS_REGION}" \
    --name "${PROJECT_NAME}-eks" \
    --query 'cluster.status' \
    --output text

  echo "Checking existing ECR repository..."

  aws ecr describe-repositories \
    --region "${AWS_REGION}" \
    --repository-names "${PROJECT_NAME}-app" \
    --query 'repositories[0].repositoryUri' \
    --output text
fi
'''
        }
      }
    }

    stage('Provision AWS Infrastructure') {
      when {
        expression {
          return params.APPLY_INFRA == true
        }
      }

      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          sh '''#!/usr/bin/env bash
set -euo pipefail

rm -f terraform/tfplan

terraform -chdir=terraform init \
  -input=false \
  -reconfigure

terraform -chdir=terraform plan \
  -input=false \
  -lock-timeout=5m \
  -out=tfplan \
  -var="project_name=${PROJECT_NAME}" \
  -var="aws_region=${AWS_REGION}"

terraform -chdir=terraform apply \
  -input=false \
  -lock-timeout=5m \
  tfplan

echo "Terraform outputs:"
terraform -chdir=terraform output
'''
        }
      }
    }

    stage('Push to Amazon ECR') {
      when {
        expression {
          return params.DEPLOY_TO_AWS == true
        }
      }

      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          script {
            env.AWS_ACCOUNT_ID = sh(
              script: '''
                aws sts get-caller-identity \
                  --query Account \
                  --output text
              ''',
              returnStdout: true
            ).trim()

            env.ECR_REGISTRY =
              "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

            env.ECR_REPOSITORY =
              "${env.PROJECT_NAME}-app"

            env.IMAGE_URI =
              "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"

            echo "ECR repository: ${env.ECR_REPOSITORY}"
            echo "ECR image URI: ${env.IMAGE_URI}"
          }

          sh '''#!/usr/bin/env bash
set -euo pipefail

echo "Checking ECR repository..."

aws ecr describe-repositories \
  --region "${AWS_REGION}" \
  --repository-names "${ECR_REPOSITORY}" \
  >/dev/null

echo "Logging in to Amazon ECR..."

aws ecr get-login-password \
  --region "${AWS_REGION}" |
  docker login \
    --username AWS \
    --password-stdin "${ECR_REGISTRY}"

echo "Tagging image..."

docker tag \
  "${LOCAL_IMAGE}" \
  "${IMAGE_URI}"

echo "Pushing image..."

docker push "${IMAGE_URI}"

echo "Verifying pushed image..."

aws ecr describe-images \
  --region "${AWS_REGION}" \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids "imageTag=${IMAGE_TAG}" \
  --query 'imageDetails[0].{Tags:imageTags,Digest:imageDigest,PushedAt:imagePushedAt}' \
  --output table

docker logout "${ECR_REGISTRY}" || true
'''
        }
      }
    }

    stage('Deploy to Amazon EKS') {
      when {
        expression {
          return params.DEPLOY_TO_AWS == true
        }
      }

      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          withEnv([
            "KUBECONFIG=${env.WORKSPACE}/.kube/config"
          ]) {
            sh '''#!/usr/bin/env bash
set -euo pipefail
set +x

print_kubernetes_diagnostics() {
  set +e

  echo "=================================================="
  echo "KUBERNETES DEPLOYMENT DIAGNOSTICS"
  echo "=================================================="

  echo "Nodes:"
  kubectl get nodes -o wide

  echo "Namespace resources:"
  kubectl \
    -n "${K8S_NAMESPACE}" \
    get all \
    -o wide

  echo "ReplicaSets:"
  kubectl \
    -n "${K8S_NAMESPACE}" \
    get replicasets \
    -o wide

  echo "Recent Kubernetes events:"
  kubectl \
    -n "${K8S_NAMESPACE}" \
    get events \
    --sort-by='.metadata.creationTimestamp'

  POD_NAMES=$(kubectl \
    -n "${K8S_NAMESPACE}" \
    get pods \
    -o jsonpath='{.items[*].metadata.name}' \
    2>/dev/null)

  for POD_NAME in ${POD_NAMES}; do
    echo "=================================================="
    echo "Pod description: ${POD_NAME}"

    kubectl \
      -n "${K8S_NAMESPACE}" \
      describe pod "${POD_NAME}"

    echo "Current logs: ${POD_NAME}"

    kubectl \
      -n "${K8S_NAMESPACE}" \
      logs "${POD_NAME}" \
      --all-containers \
      --tail=200

    echo "Previous logs: ${POD_NAME}"

    kubectl \
      -n "${K8S_NAMESPACE}" \
      logs "${POD_NAME}" \
      --all-containers \
      --previous \
      --tail=200
  done

  set -e
}

test -n "${IMAGE_URI}"

mkdir -p "$(dirname "${KUBECONFIG}")"

echo "Creating EKS kubeconfig..."

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${PROJECT_NAME}-eks" \
  --kubeconfig "${KUBECONFIG}"

echo "Checking Kubernetes access..."

kubectl get nodes -o wide

echo "Checking worker node architecture..."

NODE_ARCHITECTURES=$(kubectl get nodes \
  -o jsonpath='{range .items[*]}{.metadata.name}={.status.nodeInfo.architecture}{"\\n"}{end}')

printf '%s\n' "${NODE_ARCHITECTURES}"

if printf '%s\n' "${NODE_ARCHITECTURES}" |
   grep -vq '=amd64$'; then
  echo "ERROR: At least one EKS worker is not amd64."
  echo "The Docker image was built for linux/amd64."
  exit 1
fi

echo "Reading the database URL from AWS Secrets Manager..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${PROJECT_NAME}/database-url" \
  --query SecretString \
  --output text)

DATABASE_URL=$(printf '%s' "${SECRET_JSON}" |
  jq -r '.DATABASE_URL')

if [ -z "${DATABASE_URL}" ] ||
   [ "${DATABASE_URL}" = "null" ]; then
  echo "ERROR: DATABASE_URL was not found in Secrets Manager."
  exit 1
fi

echo "Checking Kubernetes files..."

for REQUIRED_FILE in \
  k8s/namespace.yaml \
  k8s/configmap.yaml \
  k8s/deployment.yaml \
  k8s/service.yaml \
  k8s/ingress.yaml
do
  if [ ! -f "${REQUIRED_FILE}" ]; then
    echo "ERROR: Required file is missing: ${REQUIRED_FILE}"
    exit 1
  fi
done

if ! grep -q 'IMAGE_URI' k8s/deployment.yaml; then
  echo "ERROR: k8s/deployment.yaml does not contain IMAGE_URI."
  exit 1
fi

echo "Applying namespace..."

kubectl apply \
  -f k8s/namespace.yaml

echo "Applying ConfigMap..."

kubectl apply \
  -f k8s/configmap.yaml

echo "Creating or updating database Secret..."

kubectl \
  -n "${K8S_NAMESPACE}" \
  create secret generic database-secret \
  --from-literal="DATABASE_URL=${DATABASE_URL}" \
  --dry-run=client \
  -o yaml |
  kubectl apply -f -

unset DATABASE_URL
unset SECRET_JSON

echo "Rendering Deployment manifest..."

sed \
  "s|IMAGE_URI|${IMAGE_URI}|g" \
  k8s/deployment.yaml \
  > rendered-deployment.yaml

echo "Applying Deployment..."

kubectl apply \
  -f rendered-deployment.yaml

rm -f rendered-deployment.yaml

echo "Applying Service..."

kubectl apply \
  -f k8s/service.yaml

if [ -f k8s/pod-disruption-budget.yaml ]; then
  echo "Applying Pod Disruption Budget..."

  kubectl apply \
    -f k8s/pod-disruption-budget.yaml
fi

echo "Checking AWS Load Balancer Controller..."

if kubectl \
  -n kube-system \
  get deployment aws-load-balancer-controller \
  >/dev/null 2>&1; then

  kubectl \
    -n kube-system \
    rollout status \
    deployment/aws-load-balancer-controller \
    --timeout=5m
else
  echo "WARNING: aws-load-balancer-controller deployment was not found."
  echo "Ingress will be applied, but ALB creation may fail."
fi

echo "Applying ALB Ingress..."

kubectl apply \
  -f k8s/ingress.yaml

echo "Waiting for application rollout..."

if ! kubectl \
  -n "${K8S_NAMESPACE}" \
  rollout status \
  "deployment/${K8S_DEPLOYMENT}" \
  --timeout=10m
then
  echo "ERROR: Application rollout failed."
  print_kubernetes_diagnostics
  exit 1
fi

echo "Application rollout completed successfully."

kubectl \
  -n "${K8S_NAMESPACE}" \
  get pods \
  -o wide
'''
          }
        }
      }
    }

    stage('Verify Deployment') {
      when {
        expression {
          return params.DEPLOY_TO_AWS == true
        }
      }

      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          withEnv([
            "KUBECONFIG=${env.WORKSPACE}/.kube/config"
          ]) {
            sh '''#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$(dirname "${KUBECONFIG}")"

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${PROJECT_NAME}-eks" \
  --kubeconfig "${KUBECONFIG}"

echo "EKS nodes:"

kubectl get nodes \
  -o wide

echo "Application pods:"

kubectl \
  -n "${K8S_NAMESPACE}" \
  get pods \
  -o wide

echo "Application Deployment:"

kubectl \
  -n "${K8S_NAMESPACE}" \
  get deployment \
  "${K8S_DEPLOYMENT}" \
  -o wide

echo "Application Service:"

kubectl \
  -n "${K8S_NAMESPACE}" \
  get service \
  "${K8S_SERVICE}" \
  -o wide

echo "Ingress information:"

kubectl \
  -n "${K8S_NAMESPACE}" \
  get ingress \
  "${K8S_INGRESS}" \
  -o wide

echo "Waiting for Application Load Balancer hostname..."

ALB_HOSTNAME=""

for ATTEMPT in $(seq 1 40); do
  ALB_HOSTNAME=$(kubectl \
    -n "${K8S_NAMESPACE}" \
    get ingress "${K8S_INGRESS}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null || true)

  if [ -n "${ALB_HOSTNAME}" ]; then
    echo "Application Load Balancer is ready."
    echo "Application URL: http://${ALB_HOSTNAME}"

    if command -v curl >/dev/null 2>&1; then
      echo "Testing application through the ALB..."

      for HTTP_ATTEMPT in $(seq 1 20); do
        if curl \
          --fail \
          --silent \
          --show-error \
          --max-time 10 \
          "http://${ALB_HOSTNAME}/health" \
          >/dev/null; then

          echo "Application health endpoint is responding."
          exit 0
        fi

        echo "Waiting for application health: ${HTTP_ATTEMPT}/20"
        sleep 15
      done

      echo "ERROR: ALB exists, but the health endpoint did not respond."
      exit 1
    fi

    exit 0
  fi

  echo "Waiting for ALB: ${ATTEMPT}/40"
  sleep 15
done

echo "ERROR: ALB hostname was not assigned within 10 minutes."

kubectl \
  -n "${K8S_NAMESPACE}" \
  describe ingress "${K8S_INGRESS}" || true

echo "AWS Load Balancer Controller status:"

kubectl \
  -n kube-system \
  get deployment aws-load-balancer-controller \
  -o wide || true

echo "AWS Load Balancer Controller logs:"

kubectl \
  -n kube-system \
  logs \
  deployment/aws-load-balancer-controller \
  --tail=200 || true

echo "Recent events:"

kubectl \
  -n "${K8S_NAMESPACE}" \
  get events \
  --sort-by='.metadata.creationTimestamp' || true

exit 1
'''
          }
        }
      }
    }
  }

  post {
    success {
      script {
        if (
          params.DEPLOY_TO_AWS == true &&
          env.IMAGE_URI?.trim()
        ) {
          echo 'AWS application deployment completed successfully.'
          echo "Deployed image: ${env.IMAGE_URI}"
        } else if (params.APPLY_INFRA == true) {
          echo 'AWS infrastructure provisioning completed successfully.'
          echo 'Application deployment was not requested.'
        } else {
          echo 'CI pipeline completed successfully.'
          echo 'AWS provisioning and deployment were skipped.'
        }
      }
    }

    failure {
      echo 'Pipeline failed.'
      echo 'Review the first failed stage and its Console Output.'
    }

    always {
      junit(
        allowEmptyResults: true,
        testResults: 'app/junit.xml'
      )

      sh '''#!/usr/bin/env bash
set +e

rm -rf .kube
rm -f terraform/tfplan
rm -f rendered-deployment.yaml

if [ -n "${LOCAL_IMAGE:-}" ]; then
  docker image rm \
    "${LOCAL_IMAGE}" \
    >/dev/null 2>&1 || true
fi

if [ -n "${IMAGE_URI:-}" ]; then
  docker image rm \
    "${IMAGE_URI}" \
    >/dev/null 2>&1 || true
fi

docker builder prune \
  --force \
  --filter 'until=24h' \
  >/dev/null 2>&1 || true
'''
    }
  }
}