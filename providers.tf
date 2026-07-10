terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }

  # Optional but recommended once you're comfortable: move state to an S3 backend
  # so it isn't just sitting on your laptop. Uncomment and fill in after you've
  # created the bucket manually (chicken-and-egg problem, so this stays local first).
  #
  # backend "s3" {
  #   bucket = "your-tfstate-bucket-name"
  #   key    = "devops-project/terraform.tfstate"
  #   region = "ap-south-1"
  # }
}

provider "aws" {
  region = var.aws_region
}

# Lets Kubernetes-provider resources (if you add any later, e.g. namespaces)
# authenticate against the cluster this same config creates.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
