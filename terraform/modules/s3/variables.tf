variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "enable_versioning" {
  description = "Enable S3 versioning. Required for Terraform state buckets."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for bucket encryption. Leave empty to use AES256."
  type        = string
  default     = ""
}

variable "enforce_ssl" {
  description = "Deny all non-SSL requests via bucket policy"
  type        = bool
  default     = true
}

variable "create_access_log_bucket" {
  description = "Create a companion bucket to store S3 access logs"
  type        = bool
  default     = false
}

variable "access_log_bucket_id" {
  description = "ID of an existing bucket for access logging (if not creating one)"
  type        = string
  default     = ""
}

variable "lifecycle_rules" {
  description = "List of lifecycle rules for the bucket"
  type = list(object({
    id      = string
    enabled = bool
    prefix  = optional(string, "")
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    expiration_days             = optional(number)
    noncurrent_expiration_days  = optional(number)
  }))
  default = []
}

variable "policy_statements" {
  description = "Additional IAM policy statements to attach to the bucket"
  type        = list(any)
  default     = []
}

variable "create_dynamodb_lock_table" {
  description = "Create a DynamoDB table for Terraform state locking"
  type        = bool
  default     = false
}

variable "dynamodb_table_name" {
  description = "Name for the DynamoDB lock table. Defaults to <bucket_name>-tf-locks."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
