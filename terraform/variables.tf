variable "project_name" {
  description = "Prefix used for AWS resource names."
  type        = string
  default     = "devops-starter-kit"
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR range for the project VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "kubernetes_version" {
  description = "Amazon EKS Kubernetes minor version."
  type        = string
  default     = "1.35"
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Restrict this for real use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "EC2 instance types used by the EKS managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "db_instance_class" {
  description = "Amazon RDS instance size."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  type    = string
  default = "devopsstarterkit"
}

variable "db_username" {
  type    = string
  default = "devopsadmin"
}
