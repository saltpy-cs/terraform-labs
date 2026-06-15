output "app_bucket_name" {
  description = "Name of the application S3 bucket."
  value       = aws_s3_bucket.app_data.bucket
}

output "app_bucket_arn" {
  description = "ARN of the application S3 bucket."
  value       = aws_s3_bucket.app_data.arn
}
