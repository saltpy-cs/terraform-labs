output "count_instance_ids" {
  description = "IDs of the count-based EC2 instances. Splat expression collects all [*].id values."
  # The [*] splat operator is shorthand for [for i in aws_instance.web : i.id].
  # It only works on count-managed resources (not for_each).
  value = aws_instance.web[*].id
}

output "foreach_instance_ids" {
  description = "Map of environment name to EC2 instance ID for the for_each-based instances."
  # For for_each resources you must use a for expression — splat [*] does not work.
  # This produces: { "staging" = "i-abc123", "production" = "i-def456" }
  value = { for k, v in aws_instance.env : k => v.id }
}

output "security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}
