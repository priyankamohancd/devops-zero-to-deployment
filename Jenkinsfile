pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
  }

  parameters {
    booleanParam(
      name: 'APPLY_INFRA',
      defaultValue: false,
      description: 'Create or update the AWS VPC, ECR, EKS, RDS and IAM resources with Terraform.'
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
      description: 'Prefix used for the Docker image and AWS resources.'
    )
  }

  environment {
    PYTHONUNBUFFERED = '1'

    // These names match the resources currently defined in the k8s folder.
    K8S_NAMESPACE = 'devops-starter-kit'
    K8S_DEPLOYMENT = 'devops-starter-kit-app'
    K8S_SERVICE = 'devops-starter-kit-service'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm

        script {
          // Fallback values prevent empty parameters during the first Jenkins run.
          env.PROJECT_NAME = params.PROJECT_NAME?.trim()
            ? params.PROJECT_NAME.trim()
            : 'devops-zero-to-deployment'

          env.AWS_REGION = params.AWS_REGION?.trim()
            ? params.AWS_REGION.trim()
            : 'eu-central-1'

          env.AWS_DEFAULT_REGION = env.AWS_REGION

          env.GIT_SHORT = sh(
            script: 'git rev-parse --short HEAD',
            returnStdout: true
          ).trim()

          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
          env.LOCAL_IMAGE = "${env.PROJECT_NAME}-app:${env.IMAGE_TAG}"

          env.DEPLOY_TO_AWS_EFFECTIVE = (
            params.DEPLOY_TO_AWS == true ||
            params.APPLY_INFRA == true
          ).toString()

          echo "Project name: ${env.PROJECT_NAME}"
          echo "AWS region: ${env.AWS_REGION}"
          echo "Git commit: ${env.GIT_SHORT}"
          echo "Local Docker image: ${env.LOCAL_IMAGE}"
          echo "Deploy to AWS: ${env.DEPLOY_TO_AWS_EFFECTIVE}"
        }
      }
    }

    stage('Lint and Unit Test') {
      steps {
        sh '''
          set -eux

          rm -rf .venv

          python3 -m venv .venv
          . .venv/bin/activate

          python -m pip install --upgrade pip
          pip install -r app/requirements.txt flake8

          flake8 app/ \
            --max-line-length=100 \
            --exclude=__pycache__

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
          set -eux

          terraform -chdir=terraform init -backend=false
          terraform -chdir=terraform fmt -recursive
          terraform -chdir=terraform validate
        '''
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
            set -eux

            terraform -chdir=terraform init

            terraform -chdir=terraform apply \
              -auto-approve \
              -var="project_name=${PROJECT_NAME}" \
              -var="aws_region=${AWS_REGION}"
          '''
        }
      }
    }

    stage('Build Docker Image') {
      steps {
        sh '''
          set -eux

          docker build \
            --build-arg APP_VERSION="${IMAGE_TAG}" \
            --build-arg GIT_COMMIT="${GIT_SHORT}" \
            --tag "${LOCAL_IMAGE}" \
            .
        '''
      }
    }

    stage('Security Scan') {
      steps {
        sh '''
          set -eux

          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image \
            --severity HIGH,CRITICAL \
            --exit-code 0 \
            "${LOCAL_IMAGE}"
        '''
      }
    }

    stage('Push to Amazon ECR') {
      when {
        expression {
          return params.DEPLOY_TO_AWS == true ||
                 params.APPLY_INFRA == true
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

            echo "Amazon ECR image: ${env.IMAGE_URI}"
          }

          sh '''
            set -eux

            aws ecr describe-repositories \
              --region "${AWS_REGION}" \
              --repository-names "${ECR_REPOSITORY}" \
              >/dev/null

            aws ecr get-login-password \
              --region "${AWS_REGION}" \
              | docker login \
                  --username AWS \
                  --password-stdin "${ECR_REGISTRY}"

            docker tag \
              "${LOCAL_IMAGE}" \
              "${IMAGE_URI}"

            docker push "${IMAGE_URI}"
          '''
        }
      }
    }

    stage('Deploy to Amazon EKS') {
      when {
        expression {
          return params.DEPLOY_TO_AWS == true ||
                 params.APPLY_INFRA == true
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
            set -eux

            aws eks update-kubeconfig \
              --region "${AWS_REGION}" \
              --name "${PROJECT_NAME}-eks"

            SECRET_JSON=$(aws secretsmanager get-secret-value \
              --region "${AWS_REGION}" \
              --secret-id "${PROJECT_NAME}/database-url" \
              --query SecretString \
              --output text)

            DATABASE_URL=$(printf '%s' "${SECRET_JSON}" \
              | jq -r '.DATABASE_URL')

            test -n "${DATABASE_URL}"
            test "${DATABASE_URL}" != "null"

            kubectl apply -f k8s/namespace.yaml
            kubectl apply -f k8s/configmap.yaml

            kubectl \
              -n "${K8S_NAMESPACE}" \
              create secret generic database-secret \
              --from-literal="DATABASE_URL=${DATABASE_URL}" \
              --dry-run=client \
              -o yaml \
              | kubectl apply -f -

            sed \
              "s|IMAGE_URI|${IMAGE_URI}|g" \
              k8s/deployment.yaml \
              | kubectl apply -f -

            kubectl apply -f k8s/service.yaml
            kubectl apply -f k8s/pod-disruption-budget.yaml

            kubectl \
              -n "${K8S_NAMESPACE}" \
              rollout status \
              "deployment/${K8S_DEPLOYMENT}" \
              --timeout=10m
          '''
        }
      }
    }

    stage('Verify Deployment') {
      when {
        expression {
          return params.DEPLOY_TO_AWS == true ||
                 params.APPLY_INFRA == true
        }
      }

      steps {
        sh '''
          set -eux

          kubectl \
            -n "${K8S_NAMESPACE}" \
            get pods \
            -o wide

          kubectl \
            -n "${K8S_NAMESPACE}" \
            get deployment \
            "${K8S_DEPLOYMENT}"

          kubectl \
            -n "${K8S_NAMESPACE}" \
            get service \
            "${K8S_SERVICE}"
        '''
      }
    }
  }

  post {
    success {
      script {
        if (
          env.DEPLOY_TO_AWS_EFFECTIVE == 'true' &&
          env.IMAGE_URI?.trim()
        ) {
          echo "Pipeline completed successfully."
          echo "Deployed image: ${env.IMAGE_URI}"
        } else {
          echo 'CI pipeline completed successfully.'
          echo 'AWS provisioning and deployment stages were skipped.'
        }
      }
    }

    failure {
      echo 'Pipeline failed. Open the failed stage in Console Output for the exact error.'
    }

    always {
      junit(
        allowEmptyResults: true,
        testResults: 'app/junit.xml'
      )

      sh 'docker image prune -f || true'
    }
  }
}