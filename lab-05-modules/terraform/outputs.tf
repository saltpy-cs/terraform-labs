output "network_id" {
  description = "ID of the VPC network, sourced from the vpc module output."
  value       = module.vpc.network_id
}

output "subnet_id" {
  description = "ID of the subnetwork, sourced from the vpc module output."
  value       = module.vpc.subnet_id
}

output "instance_external_ip" {
  description = "External IP address of the compute instance."
  value       = google_compute_instance.app.network_interface[0].access_config[0].nat_ip
}
