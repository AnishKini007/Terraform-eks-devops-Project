locals {
  name = "${var.project_name}-${var.environment}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# VPC — public subnets for the NAT/load balancers, private subnets for the
# EKS nodes and RDS instance. Using the community module instead of hand-
# rolling this: it's the industry-standard way to do it and saves ~150 lines
# of boilerplate route-table/IGW/NAT wiring.
# ---------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = local.name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT gateway, not one per AZ — keeps cost down for a portfolio project
  enable_dns_hostnames = true

  # Required tags so the EKS/ALB controllers can auto-discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${local.name}"        = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${local.name}"        = "shared"
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# EKS cluster with a managed node group
# ---------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  cluster_endpoint_public_access = true # fine for a portfolio project; in production you'd lock this to a VPN/bastion

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
    }
  }

  enable_cluster_creator_admin_permissions = true

  tags = local.tags
}

# ---------------------------------------------------------------------------
# RDS — private, reachable only from the EKS node security group
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db-subnets"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Allow DB traffic only from EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Postgres from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-db"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = false # single-AZ keeps this cheap; note in interviews you'd flip this for prod
  publicly_accessible    = false
  skip_final_snapshot    = true # portfolio project — no need to keep a snapshot on destroy
  deletion_protection    = false
  backup_retention_period = 0

  tags = local.tags
}
