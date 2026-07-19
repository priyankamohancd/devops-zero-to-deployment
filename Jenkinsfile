pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    timeout(time: 90, unit: 'MINUTES')
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
      description: 'Push the Docker image to Amazon ECR and deploy it to Amazon EKS.'
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
     * These values must match metadata.name and namespace
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

          env.PROJECT_NAME = selectedProject ?: 'devops-zero-to-deployment'
          env.AWS_REGION = selectedRegion ?: 'eu-central-1'
          env.AWS_DEFAULT_REGION = env.AWS_REGION

          env.GIT_SHORT = sh(
            script: 'git rev-parse --short HEAD',
            returnStdout: true
          ).trim()

          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
          env.LOCAL_IMAGE = "${env.PROJECT_NAME}-app:${env.IMAGE_TAG}"

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
        sh '''
          set -eu

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
        sh '''
          set -eu

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
        sh '''
          set -eu

          docker build \
            --build-arg "APP_VERSION=${IMAGE_TAG}" \
            --build-arg "GIT_COMMIT=${GIT_SHORT}" \
            --tag "${LOCAL_IMAGE}" \
            .
        '''
      }
    }

    stage('Security Scan') {
      steps {
        sh '''
          set -eu

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
          sh '''
            set -eu

            echo "AWS identity used by Jenkins:"
            aws sts get-caller-identity

            if [ "${APPLY_INFRA_EFFECTIVE}" = "true" ]; then
              echo "Testing EC2 Availability Zone access:"

              aws ec2 describe-availability-zones \
                --region "${AWS_REGION}" \
                --query 'AvailabilityZones[?State==`available`].ZoneName' \
                --output table
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
          sh '''
            set -eu

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

          sh '''
            set -eu

            echo "Checking whether the ECR repository exists..."

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

            echo "Tagging Docker image..."

            docker tag \
              "${LOCAL_IMAGE}" \
              "${IMAGE_URI}"

            echo "Pushing image to Amazon ECR..."

            docker push "${IMAGE_URI}"

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
            sh '''
              set -eu

              test -n "${IMAGE_URI}"

              mkdir -p "$(dirname "${KUBECONFIG}")"

              echo "Creating EKS kubeconfig..."

              aws eks update-kubeconfig \
                --region "${AWS_REGION}" \
                --name "${PROJECT_NAME}-eks" \
                --kubeconfig "${KUBECONFIG}"

              echo "Checking Kubernetes access..."

              kubectl get nodes

              echo "Reading database URL from AWS Secrets Manager..."

              SECRET_JSON=$(aws secretsmanager get-secret-value \
                --region "${AWS_REGION}" \
                --secret-id "${PROJECT_NAME}/database-url" \
                --query SecretString \
                --output text)

              DATABASE_URL=$(printf '%s' "${SECRET_JSON}" |
                jq -r '.DATABASE_URL')

              test -n "${DATABASE_URL}"
              test "${DATABASE_URL}" != "null"

              echo "Applying Kubernetes namespace..."

              kubectl apply \
                -f k8s/namespace.yaml

              echo "Applying ConfigMap..."

              kubectl apply \
                -f k8s/configmap.yaml

              echo "Creating database Secret..."

              kubectl \
                -n "${K8S_NAMESPACE}" \
                create secret generic database-secret \
                --from-literal="DATABASE_URL=${DATABASE_URL}" \
                --dry-run=client \
                -o yaml |
                kubectl apply -f -

              echo "Applying application Deployment..."

              sed \
                "s|IMAGE_URI|${IMAGE_URI}|g" \
                k8s/deployment.yaml |
                kubectl apply -f -

              echo "Applying Kubernetes Service..."

              kubectl apply \
                -f k8s/service.yaml

              if [ -f k8s/pod-disruption-budget.yaml ]; then
                echo "Applying Pod Disruption Budget..."

                kubectl apply \
                  -f k8s/pod-disruption-budget.yaml
              fi

              if [ -f k8s/ingress.yaml ]; then
                echo "Applying ALB Ingress..."

                kubectl apply \
                  -f k8s/ingress.yaml
              fi

              echo "Waiting for application rollout..."

              kubectl \
                -n "${K8S_NAMESPACE}" \
                rollout status \
                "deployment/${K8S_DEPLOYMENT}" \
                --timeout=10m
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
            sh '''
              set -eu

              mkdir -p "$(dirname "${KUBECONFIG}")"

              aws eks update-kubeconfig \
                --region "${AWS_REGION}" \
                --name "${PROJECT_NAME}-eks" \
                --kubeconfig "${KUBECONFIG}"

              echo "EKS nodes:"
              kubectl get nodes -o wide

              echo "Application pods:"
              kubectl \
                -n "${K8S_NAMESPACE}" \
                get pods \
                -o wide

              echo "Application deployment:"
              kubectl \
                -n "${K8S_NAMESPACE}" \
                get deployment \
                "${K8S_DEPLOYMENT}"

              echo "Application service:"
              kubectl \
                -n "${K8S_NAMESPACE}" \
                get service \
                "${K8S_SERVICE}"

              if [ ! -f k8s/ingress.yaml ]; then
                echo "No ingress.yaml file was found."
                echo "Kubernetes deployment verification completed."
                exit 0
              fi

              echo "Ingress information:"
              kubectl \
                -n "${K8S_NAMESPACE}" \
                get ingress

              echo "Waiting for Application Load Balancer hostname..."

              ALB_HOSTNAME=""

              for attempt in $(seq 1 40); do
                ALB_HOSTNAME=$(kubectl \
                  -n "${K8S_NAMESPACE}" \
                  get ingress "${K8S_INGRESS}" \
                  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
                  2>/dev/null || true)

                if [ -n "${ALB_HOSTNAME}" ]; then
                  echo "Application Load Balancer is ready."
                  echo "Application URL: http://${ALB_HOSTNAME}"
                  exit 0
                fi

                echo "Waiting for ALB: attempt ${attempt}/40"
                sleep 15
              done

              echo "ALB hostname was not assigned within 10 minutes."

              kubectl \
                -n "${K8S_NAMESPACE}" \
                describe ingress "${K8S_INGRESS}" || true

              echo "AWS Load Balancer Controller logs:"

              kubectl \
                -n kube-system \
                logs \
                deployment/aws-load-balancer-controller \
                --tail=100 || true

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
      echo 'Open the failed stage and Console Output to see the exact error.'
    }

    always {
      junit(
        allowEmptyResults: true,
        testResults: 'app/junit.xml'
      )

      sh '''
        rm -rf .kube
        rm -f terraform/tfplan

        if [ -n "${LOCAL_IMAGE:-}" ]; then
          docker image rm "${LOCAL_IMAGE}" >/dev/null 2>&1 || true
        fi

        if [ -n "${IMAGE_URI:-}" ]; then
          docker image rm "${IMAGE_URI}" >/dev/null 2>&1 || true
        fi
      '''
    }
  }
}