variable "identifier" {
  description = "Unique identifier for the RDS instance (used in resource names)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage_gb" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Maximum storage autoscaling limit in GB"
  type        = number
  default     = 100
}

variable "database_name" {
  description = "Name of the initial database to create"
  type        = string
}

variable "master_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "vpc_id" {
  description = "VPC ID where the RDS instance will be deployed"
  type        = string
}

variable "db_subnet_group_name" {
  description = "Name of the DB subnet group (from VPC module output)"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to connect to RDS on port 5432"
  type        = list(string)
  default     = []
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Availability zone for single-AZ deployments"
  type        = string
  default     = null
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "alarm_sns_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications. Leave empty to skip."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
