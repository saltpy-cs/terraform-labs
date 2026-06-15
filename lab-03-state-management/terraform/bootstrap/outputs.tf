output "bucket_name" {
  description = "Name of the S3 bucket that stores Terraform state. Copy this value into terraform/app/main.tf."
  value       = aws_s3_bucket.state.bucket
}

output "table_name" {
  description = "Name of the DynamoDB table used for state locking. Copy this value into terraform/app/main.tf."
  value       = aws_dynamodb_table.locks.name
}

output "bucket_arn" {
  description = "ARN of the state S3 bucket."
  value       = aws_s3_bucket.state.arn
}
