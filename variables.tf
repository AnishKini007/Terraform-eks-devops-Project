variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1" # Mumbai — closest region to Bengaluru
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "devops-portfolio"
}

variable "environment" {
  description = "Environment tag (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "db_engine" {
  description = "RDS engine"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  type    = string
  default = "16.3"
}

variable "db_instance_class" {
  description = "RDS instance size — keep small, this is a portfolio project not production"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "appadmin"
}

variable "db_password" {
  description = "Master password for RDS. Do NOT commit a real value — pass via terraform.tfvars (gitignored) or TF_VAR_db_password env var."
  type        = string
  sensitive   = true
}
