output "bucket_name" {
  description = "GCS bucket name"
  value       = module.gcs_bucket.bucket_name
}

output "bucket_url" {
  description = "GCS bucket URL (gs://...)"
  value       = module.gcs_bucket.bucket_url
}

output "bucket_self_link" {
  description = "GCS bucket self link URI"
  value       = module.gcs_bucket.bucket_self_link
}

output "versioning_enabled" {
  description = "Whether object versioning is enabled on the bucket"
  value       = module.gcs_bucket.versioning_enabled
}
