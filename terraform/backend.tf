terraform {
  backend "s3" {
    bucket       = "priyanka-terraform-state-997836554394-eu-central-1"
    key          = "devops-zero-to-deployment/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}