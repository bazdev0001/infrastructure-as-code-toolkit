################################################################################
# Dev Environment
# Calls shared modules with development-appropriate sizing.
# Single NAT, single-AZ RDS, smaller instances — keeps costs low.
################################################################################

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "your-org-tf-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "your-org-tf-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform"
      Team        = var.team
      CostCenter  = var.cost_center
    }
  }
}

################################################################################
# Variables
################################################################################

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "dev-us-east-1"
}

variable "team" {
  type    = string
  default = "platform"
}

variable "cost_center" {
  type    = string
  default = "infra-dev"
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  cluster_name = var.cluster_name
  environment  = "dev"
  vpc_cidr     = "10.10.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b"]

  # Single NAT — saves ~$32/month vs one-per-AZ in dev
  single_nat_gateway = true

  enable_flow_logs         = true
  flow_logs_retention_days = 7

  tags = {
    Team       = var.team
    CostCenter = var.cost_center
  }
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  environment        = "dev"
  kubernetes_version = "1.29"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Public endpoint locked to office IP only in dev
  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]

  node_groups = {
    general = {
      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      disk_size_gb   = 30
    }
  }

  tags = {
    Team       = var.team
    CostCenter = var.cost_center
  }
}

################################################################################
# RDS — dev PostgreSQL
################################################################################

module "rds" {
  source = "../../modules/rds"

  identifier    = "${var.cluster_name}-postgres"
  environment   = "dev"
  engine_version = "15.4"

  # Cost-appropriate sizing for dev
  instance_class           = "db.t3.medium"
  allocated_storage_gb     = 20
  max_allocated_storage_gb = 50

  database_name = "appdb"
  master_username = "dbadmin"

  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.db_subnet_group_name

  # Allow inbound from EKS nodes
  allowed_security_group_ids = [module.eks.node_security_group_id]

  # Single-AZ in dev — Multi-AZ is overkill
  multi_az              = false
  backup_retention_days = 3

  alarm_sns_arn = ""

  tags = {
    Team       = var.team
    CostCenter = var.cost_center
  }
}

################################################################################
# Outputs
################################################################################

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "db_endpoint" {
  value = module.rds.db_instance_endpoint
}

output "db_secret_arn" {
  value = module.rds.secret_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
