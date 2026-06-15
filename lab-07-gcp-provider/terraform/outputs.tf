output "service_account_email" {
  description = "Email address of the application service account"
  value       = google_service_account.app.email
}

output "us_bucket_url" {
  description = "US GCS bucket URL in gs:// format"
  value       = "gs://${google_storage_bucket.us.name}"
}

output "europe_bucket_url" {
  description = "Europe GCS bucket URL (created via aliased google.europe provider)"
  value       = "gs://${google_storage_bucket.europe.name}"
}

output "app_instance_name" {
  description = "GCE instance name"
  value       = google_compute_instance.app.name
}

output "my_external_ip" {
  description = "Your public IP address as seen from the internet (fetched by the http provider)"
  value       = data.http.metadata.response_body
}
