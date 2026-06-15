output "instance_ids" {
  description = "Map of environment name to EC2 instance ID"
  # for expression over a for_each resource produces a map.
  # for_each resources cannot use splat syntax ([*]).
  value = { for k, v in aws_instance.app : k => v.id }
}

output "instance_ips" {
  description = "Map of environment name to public IP address"
  value       = { for k, v in aws_instance.app : k => v.public_ip }
}

output "enabled_environments" {
  description = "List of environments that were provisioned (varies based on enable_production)"
  value       = local.enabled_envs
}

output "instance_names" {
  description = "List of instance name strings built by the for expression in locals"
  value       = local.instance_names
}

output "security_group_rules_debug" {
  description = "The security group rules as built by the for expression in locals"
  value       = local.security_group_rules
}
