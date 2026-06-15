output "bucket_name" {
  description = "Name of the GCS bucket that stores Terraform state. Copy this value into terraform/app/main.tf."
  value       = google_storage_bucket.tf_state.name
}

output "bucket_url" {
  description = "gs:// URL of the state bucket. Use with gsutil or gcloud storage commands."
  value       = "gs://${google_storage_bucket.tf_state.name}"
}
