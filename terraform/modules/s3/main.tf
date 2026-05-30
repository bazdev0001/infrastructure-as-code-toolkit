################################################################################
# S3 Module
# Creates an S3 bucket with versioning, encryption, lifecycle policies,
# access logging, and optionally configures it as a Terraform state backend
# with DynamoDB locking.
################################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Module      = "s3"
    ManagedBy   = "terraform"
    Environment = var.environment
  })
}

################################################################################
# Access Logging Bucket (if not external)
################################################################################

resource "aws_s3_bucket" "logs" {
  count  = var.create_access_log_bucket ? 1 : 0
  bucket = "${var.bucket_name}-access-logs"

  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name    = "${var.bucket_name}-access-logs"
    Purpose = "access-logs"
  })
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count  = var.create_access_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  count  = var.create_access_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  acl    = "log-delivery-write"

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.create_access_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.create_access_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

################################################################################
# Main Bucket
################################################################################

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = var.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.kms_key_arn != ""
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "this" {
  count  = var.create_access_log_bucket || var.access_log_bucket_id != "" ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.create_access_log_bucket ? aws_s3_bucket.logs[0].id : var.access_log_bucket_id
  target_prefix = "s3-access-logs/${var.bucket_name}/"
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = lookup(rule.value, "prefix", "")
      }

      dynamic "transition" {
        for_each = lookup(rule.value, "transitions", [])
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = lookup(rule.value, "expiration_days", null) != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = lookup(rule.value, "noncurrent_expiration_days", null) != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_expiration_days
        }
      }
    }
  }
}

################################################################################
# Bucket Policy
################################################################################

data "aws_iam_policy_document" "this" {
  count = length(var.policy_statements) > 0 || var.enforce_ssl ? 1 : 0

  dynamic "statement" {
    for_each = var.policy_statements
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = lookup(statement.value, "effect", "Allow")
      actions   = statement.value.actions
      resources = [for r in statement.value.resources : r == "*" ? "${aws_s3_bucket.this.arn}/*" : "${aws_s3_bucket.this.arn}/${r}"]

      dynamic "principals" {
        for_each = lookup(statement.value, "principals", [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }
    }
  }

  dynamic "statement" {
    for_each = var.enforce_ssl ? [1] : []
    content {
      sid     = "DenyHTTP"
      effect  = "Deny"
      actions = ["s3:*"]
      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*"
      ]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      condition {
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["false"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = length(var.policy_statements) > 0 || var.enforce_ssl ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this[0].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

################################################################################
# DynamoDB Table for Terraform State Locking
################################################################################

resource "aws_dynamodb_table" "terraform_locks" {
  count = var.create_dynamodb_lock_table ? 1 : 0

  name         = var.dynamodb_table_name != "" ? var.dynamodb_table_name : "${var.bucket_name}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name    = "${var.bucket_name}-tf-locks"
    Purpose = "terraform-state-locking"
  })
}
