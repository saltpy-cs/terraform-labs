output "bucket_url" {
  description = "Primary GCS bucket URL in gs:// format"
  value       = "gs://${google_storage_bucket.main.name}"
}

output "europe_bucket_url" {
  description = "Europe GCS bucket URL (created via aliased provider)"
  value       = "gs://${google_storage_bucket.europe.name}"
}

output "instance_self_link" {
  description = "GCE instance self-link (full resource URL)"
  value       = google_compute_instance.web.self_link
}

output "instance_external_ip" {
  description = "GCE instance external IP address"
  value       = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}

output "network_id" {
  description = "VPC network resource ID"
  value       = google_compute_network.main.id
}
