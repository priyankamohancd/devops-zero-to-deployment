PROJECT_NAME ?= devops-starter-kit
AWS_REGION ?= eu-central-1

.PHONY: help install lint test local-up local-down local-logs local-smoke \
        jenkins-up jenkins-down terraform-fmt terraform-validate aws-deploy aws-destroy clean

help:
	@echo "Available targets:"
	@echo "  make install             Install Python dependencies"
	@echo "  make lint                Run flake8"
	@echo "  make test                Run pytest"
	@echo "  make local-up            Start app + PostgreSQL with Docker Compose"
	@echo "  make local-down          Stop the local stack"
	@echo "  make local-smoke         Test local health endpoints"
	@echo "  make jenkins-up          Start the custom Jenkins server"
	@echo "  make terraform-validate  Format-check and validate Terraform"
	@echo "  make aws-deploy          Provision AWS, push to ECR, deploy to EKS"
	@echo "  make aws-destroy         Remove Kubernetes resources and AWS infrastructure"

install:
	python3 -m pip install -r app/requirements.txt flake8

lint:
	flake8 app/ --max-line-length=100 --exclude=__pycache__

test:
	cd app && pytest -v

local-up:
	docker compose up -d --build
	@echo "Application: http://localhost:5000"

local-down:
	docker compose down

local-logs:
	docker compose logs -f web database

local-smoke:
	./scripts/smoke-test.sh http://localhost:5000

jenkins-up:
	docker compose -f jenkins/docker-compose.yml up -d --build
	@echo "Jenkins: http://localhost:8080"

jenkins-down:
	docker compose -f jenkins/docker-compose.yml down

terraform-fmt:
	terraform -chdir=terraform fmt -recursive

terraform-validate:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform fmt -recursive
	terraform -chdir=terraform validate

aws-deploy:
	PROJECT_NAME=$(PROJECT_NAME) AWS_REGION=$(AWS_REGION) ./scripts/deploy-aws.sh

aws-destroy:
	PROJECT_NAME=$(PROJECT_NAME) AWS_REGION=$(AWS_REGION) ./scripts/destroy-aws.sh

clean:
	docker compose down -v --remove-orphans || true
	rm -rf .venv app/.pytest_cache app/__pycache__ terraform/.terraform
