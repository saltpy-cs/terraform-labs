output "bucket_id" {
  description = "S3 bucket ID (name)"
  value       = module.s3_bucket.bucket_id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.s3_bucket.bucket_arn
}

output "bucket_domain_name" {
  description = "S3 bucket regional domain name"
  value       = module.s3_bucket.bucket_domain_name
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket"
  value       = module.s3_bucket.versioning_enabled
}
