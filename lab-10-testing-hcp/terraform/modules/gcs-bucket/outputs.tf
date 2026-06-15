output "bucket_name" {
  description = "The GCS bucket name"
  value       = google_storage_bucket.this.name
}

output "bucket_url" {
  description = "The GCS bucket URL in gs:// format"
  value       = "gs://${google_storage_bucket.this.name}"
}

output "bucket_self_link" {
  description = "The URI of the bucket"
  value       = google_storage_bucket.this.self_link
}

output "versioning_enabled" {
  description = "Whether object versioning is enabled on the bucket"
  value       = google_storage_bucket.this.versioning[0].enabled
}
