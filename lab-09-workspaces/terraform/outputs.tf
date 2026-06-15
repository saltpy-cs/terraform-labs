output "workspace" {
  description = "The currently active Terraform workspace"
  value       = terraform.workspace
}

output "machine_type_used" {
  description = "The GCE machine type selected for this workspace by the lookup() expression"
  value       = local.machine_type
}

output "instance_name" {
  description = "GCE instance name"
  value       = google_compute_instance.app.name
}

output "environment_summary" {
  description = "Summary of key values for the current workspace deployment"
  value = {
    workspace    = terraform.workspace
    machine_type = local.machine_type
    instance     = google_compute_instance.app.name
  }
}
