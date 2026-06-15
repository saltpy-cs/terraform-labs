output "workspace" {
  description = "The currently active Terraform workspace"
  value       = terraform.workspace
}

output "instance_type_used" {
  description = "The EC2 instance type selected for this workspace by the lookup() expression"
  value       = local.instance_type
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "environment_summary" {
  description = "Summary of key values for the current workspace deployment"
  value = {
    workspace     = terraform.workspace
    environment   = local.env
    instance_type = local.instance_type
    instance_id   = aws_instance.app.id
  }
}
