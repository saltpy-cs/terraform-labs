# These outputs are the ONLY values the root module can access from this
# child module. There is no implicit access to resource attributes — if a
# value is not declared here, it does not exist from the caller's perspective.

output "network_id" {
  description = "The unique identifier of the VPC network."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "The URI of the VPC network (used when attaching other resources)."
  value       = google_compute_network.this.self_link
}

output "subnet_id" {
  description = "The unique identifier of the subnetwork."
  value       = google_compute_subnetwork.this.id
}

output "subnet_name" {
  description = "The name of the subnetwork."
  value       = google_compute_subnetwork.this.name
}

output "subnet_self_link" {
  description = "The URI of the subnetwork (used in instance network_interface blocks)."
  value       = google_compute_subnetwork.this.self_link
}
