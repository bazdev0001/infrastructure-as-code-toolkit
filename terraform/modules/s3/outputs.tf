output "bucket_id" {
  description = "Name (ID) of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region the bucket is in"
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "Bucket domain name (for use in policies and URLs)"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "dynamodb_lock_table_name" {
  description = "Name of the DynamoDB lock table (empty if not created)"
  value       = var.create_dynamodb_lock_table ? aws_dynamodb_table.terraform_locks[0].name : ""
}

output "dynamodb_lock_table_arn" {
  description = "ARN of the DynamoDB lock table (empty if not created)"
  value       = var.create_dynamodb_lock_table ? aws_dynamodb_table.terraform_locks[0].arn : ""
}
