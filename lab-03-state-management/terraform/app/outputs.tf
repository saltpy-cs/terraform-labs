output "app_bucket_name" {
  description = "Name of the application GCS bucket."
  value       = google_storage_bucket.app_data.name
}

output "app_bucket_url" {
  description = "gs:// URL of the application GCS bucket."
  value       = "gs://${google_storage_bucket.app_data.name}"
}
