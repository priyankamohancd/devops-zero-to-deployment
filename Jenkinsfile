pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(
      name: 'APPLY_INFRA',
      defaultValue: false,
      description: 'Create or update EKS, ECR, RDS, VPC and IAM with Terraform.'
    )
    string(name: 'AWS_REGION', defaultValue: 'eu-central-1', description: 'AWS region')
    string(name: 'PROJECT_NAME', defaultValue: 'devops-starter-kit', description: 'Resource prefix')
  }

  environment {
    AWS_DEFAULT_REGION = "${params.AWS_REGION}"
    PYTHONUNBUFFERED = '1'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
        }
      }
    }

    stage('Lint and Unit Test') {
      steps {
        sh '''
          python3 -m venv .venv
          . .venv/bin/activate
          pip install --upgrade pip
          pip install -r app/requirements.txt flake8
          flake8 app/ --max-line-length=100 --exclude=__pycache__
          cd app
          pytest -v --tb=short --junitxml=junit.xml
        '''
      }
    }

    stage('Validate Terraform') {
      steps {
        sh '''
          terraform -chdir=terraform init -backend=false
          terraform -chdir=terraform fmt -recursive
          terraform -chdir=terraform validate
        '''
      }
    }

    stage('Provision AWS Infrastructure') {
      when {
        expression { return params.APPLY_INFRA }
      }
      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          sh '''
            terraform -chdir=terraform init
            terraform -chdir=terraform apply -auto-approve \
              -var="project_name=${PROJECT_NAME}" \
              -var="aws_region=${AWS_REGION}"
          '''
        }
      }
    }

    stage('Build Docker Image') {
      steps {
        sh '''
          docker build \
            --build-arg APP_VERSION=${IMAGE_TAG} \
            --build-arg GIT_COMMIT=${GIT_SHORT} \
            --tag ${PROJECT_NAME}-app:${IMAGE_TAG} .
        '''
      }
    }

    stage('Security Scan') {
      steps {
        sh '''
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image \
            --severity HIGH,CRITICAL \
            --exit-code 0 \
            ${PROJECT_NAME}-app:${IMAGE_TAG}
        '''
      }
    }

    stage('Push to Amazon ECR') {
      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          script {
            env.AWS_ACCOUNT_ID = sh(
              script: 'aws sts get-caller-identity --query Account --output text',
              returnStdout: true
            ).trim()
            env.ECR_REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${params.AWS_REGION}.amazonaws.com"
            env.ECR_REPOSITORY = "${params.PROJECT_NAME}-app"
            env.IMAGE_URI = "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"
          }
          sh '''
            aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} >/dev/null
            aws ecr get-login-password --region ${AWS_REGION} \
              | docker login --username AWS --password-stdin ${ECR_REGISTRY}
            docker tag ${PROJECT_NAME}-app:${IMAGE_TAG} ${IMAGE_URI}
            docker push ${IMAGE_URI}
          '''
        }
      }
    }

    stage('Deploy to Amazon EKS') {
      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          credentialsId: 'aws-credentials',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
        ]]) {
          sh '''
            aws eks update-kubeconfig \
              --region ${AWS_REGION} \
              --name ${PROJECT_NAME}-eks

            SECRET_JSON=$(aws secretsmanager get-secret-value \
              --region ${AWS_REGION} \
              --secret-id ${PROJECT_NAME}/database-url \
              --query SecretString \
              --output text)
            DATABASE_URL=$(printf '%s' "$SECRET_JSON" | jq -r '.DATABASE_URL')

            kubectl apply -f k8s/namespace.yaml
            kubectl apply -f k8s/configmap.yaml
            kubectl -n devops-starter-kit create secret generic database-secret \
              --from-literal="DATABASE_URL=$DATABASE_URL" \
              --dry-run=client -o yaml | kubectl apply -f -
            sed "s|IMAGE_URI|${IMAGE_URI}|g" k8s/deployment.yaml | kubectl apply -f -
            kubectl apply -f k8s/service.yaml
            kubectl apply -f k8s/pod-disruption-budget.yaml
            kubectl -n devops-starter-kit rollout status \
              deployment/devops-starter-kit-app --timeout=10m
          '''
        }
      }
    }

    stage('Verify') {
      steps {
        sh '''
          kubectl -n devops-starter-kit get pods
          kubectl -n devops-starter-kit get service devops-starter-kit-service
        '''
      }
    }
  }

  post {
    success {
      echo "Deployment completed with image ${env.IMAGE_URI}"
    }
    always {
      junit allowEmptyResults: true, testResults: 'app/junit.xml'
      sh 'docker image prune -f || true'
    }
  }
}
