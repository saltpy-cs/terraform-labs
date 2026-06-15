output "instance_ids" {
  description = "Map of environment name to GCE instance ID"
  # for expression over a for_each resource produces a map.
  # for_each resources cannot use splat syntax ([*]) — see Exercise 7.
  value = { for k, v in google_compute_instance.app : k => v.id }
}

output "instance_ips" {
  description = "Map of environment name to external IP address"
  value       = { for k, v in google_compute_instance.app : k => v.network_interface[0].access_config[0].nat_ip }
}

output "enabled_environments" {
  description = "List of environments that were provisioned (varies based on enable_production)"
  value       = local.enabled_envs
}

output "prod_bucket" {
  description = "Prod GCS bucket name, or 'not created' when enable_production=false"
  value       = var.enable_production ? google_storage_bucket.prod_data[0].name : "not created"
}
