################################################################################
# Production Environment
# High availability: Multi-AZ RDS, one NAT per AZ, larger instances,
# strict endpoint access, enhanced monitoring, deletion protection.
################################################################################

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "your-org-tf-state"
    key            = "prod/terraform.tfstate"
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
      Environment = "prod"
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
  default = "prod-us-east-1"
}

variable "team" {
  type    = string
  default = "platform"
}

variable "cost_center" {
  type    = string
  default = "infra-prod"
}

variable "api_server_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API server in production"
  type        = list(string)
  # Override this in terraform.tfvars — do not leave as 0.0.0.0/0 in prod
  default = ["10.0.0.0/8"]
}

variable "alarm_sns_arn" {
  description = "SNS topic ARN for CloudWatch alarms (PagerDuty or similar)"
  type        = string
  default     = ""
}

################################################################################
# VPC — 3 AZs, one NAT per AZ for HA
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  cluster_name = var.cluster_name
  environment  = "prod"
  vpc_cidr     = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # One NAT per AZ — if an AZ fails, other AZs can still reach the internet
  single_nat_gateway = false

  enable_flow_logs         = true
  flow_logs_retention_days = 90

  tags = {
    Team       = var.team
    CostCenter = var.cost_center
  }
}

################################################################################
# EKS Cluster — HA node groups, API server access controlled
################################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  environment        = "prod"
  kubernetes_version = "1.29"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Restrict API server access in production
  endpoint_public_access = true
  public_access_cidrs    = var.api_server_allowed_cidrs

  node_groups = {
    # General workload nodes
    general = {
      instance_types = ["m5.xlarge", "m5a.xlarge"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 3
      min_size       = 3
      max_size       = 20
      disk_size_gb   = 50
    }

    # Spot nodes for batch / less critical workloads
    spot = {
      instance_types = ["m5.large", "m5a.large", "m4.large"]
      capacity_type  = "SPOT"
      desired_size   = 2
      min_size       = 0
      max_size       = 15
      disk_size_gb   = 50
      labels = {
        "workload-type" = "spot"
      }
      taints = [{
        key    = "spot-instance"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  tags = {
    Team       = var.team
    CostCenter = var.cost_center
  }
}

################################################################################
# RDS — Multi-AZ PostgreSQL, deletion protection, 30-day backups
################################################################################

module "rds" {
  source = "../../modules/rds"

  identifier     = "${var.cluster_name}-postgres"
  environment    = "prod"
  engine_version = "15.4"

  # Production-grade instance
  instance_class           = "db.r6g.xlarge"
  allocated_storage_gb     = 100
  max_allocated_storage_gb = 500

  database_name   = "appdb"
  master_username = "dbadmin"

  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.db_subnet_group_name

  # Allow inbound from EKS nodes only
  allowed_security_group_ids = [module.eks.node_security_group_id]

  # High availability
  multi_az = true

  # Production backup policy
  backup_retention_days = 30

  alarm_sns_arn = var.alarm_sns_arn

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
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "db_endpoint" {
  value     = module.rds.db_instance_endpoint
  sensitive = true
}

output "db_secret_arn" {
  value = module.rds.secret_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nat_public_ips" {
  description = "Add these IPs to external service allowlists"
  value       = module.vpc.nat_public_ips
}
