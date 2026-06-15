output "network_id" {
  description = "ID of the VPC network."
  value       = google_compute_network.main.id
}

output "subnet_id" {
  description = "ID of the public subnet."
  value       = google_compute_subnetwork.public.id
}

output "instance_name" {
  description = "Name of the GCE instance."
  value       = google_compute_instance.main.name
}

output "instance_external_ip" {
  description = "External (public) IP address of the GCE instance."
  value       = google_compute_instance.main.network_interface[0].access_config[0].nat_ip
}

output "instance_self_link" {
  description = "Self-link URL of the GCE instance. Used by other GCP resources that reference this instance."
  value       = google_compute_instance.main.self_link
}

output "debian_image" {
  description = "Name of the Debian 12 image resolved by the data source. Shows that data sources are evaluated at plan time."
  value       = data.google_compute_image.debian.name
}
