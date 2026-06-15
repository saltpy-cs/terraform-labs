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

output "all_subnets_flat" {
  description = "The flattened subnet map produced by local.all_subnets — one entry per subnet across all VPCs"
  value       = local.all_subnets
}

output "subnet_names_by_vpc" {
  description = "Grouped view: map of vpc_name to list of subnet names it owns"
  value = {
    for vpc_name in keys(var.vpc_config) :
      vpc_name => [
        for k, v in local.all_subnets : k
        if v.vpc_name == vpc_name
      ]
  }
}

output "env_set_vs_list" {
  description = "Shows the difference between var.environments (list) and local.env_set (set)"
  value = {
    original_list = var.environments
    as_set        = local.env_set
    sorted_list   = local.env_list_sorted
  }
}
