output "app_name" {
  description = "The application name as provided"
  value       = var.app_name
}

output "name_prefix" {
  description = "The computed name prefix (app_name + environment)"
  value       = local.name_prefix
}

output "replica_names" {
  description = "Names of all replica resources"
  value       = local.replica_names
}

output "replica_ids" {
  description = "Random IDs for each replica"
  value       = random_id.replica[*].hex
}

output "instance_type" {
  description = "The EC2 instance type selected for this environment"
  value       = local.instance_type
}

output "monitoring_enabled" {
  description = "Whether monitoring is active (forced true in prod)"
  value       = local.monitoring_enabled
}

output "service_endpoint" {
  description = "The service endpoint string built from service_config"
  value       = local.service_endpoint
}

output "mock_secret" {
  description = "The secret value — marked sensitive, suppressed in normal output"
  value       = var.mock_secret
  sensitive   = true
}

output "external_info" {
  description = "Values returned by the external data source"
  value       = data.external.info.result
}

output "common_tags" {
  description = "The common tags map applied to all resources"
  value       = local.common_tags
}
