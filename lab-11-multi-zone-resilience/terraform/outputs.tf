output "load_balancer_ip" {
  description = "External IP of the Network Load Balancer. Wait ~2 minutes after apply before testing."
  value       = google_compute_forwarding_rule.app.ip_address
}

output "mig_name" {
  description = "Name of the Regional Managed Instance Group."
  value       = google_compute_region_instance_group_manager.app.name
}

output "app_data_bucket" {
  description = "GCS bucket URL for resilient app data storage."
  value       = "gs://${google_storage_bucket.app_data.name}"
}

output "health_check_command" {
  description = "Command to check backend health status."
  value       = "gcloud compute backend-services get-health ${google_compute_region_backend_service.app.name} --region=${var.gcp_region}"
}

output "list_instances_command" {
  description = "Command to list MIG instances and their zones."
  value       = "gcloud compute instance-groups managed list-instances ${google_compute_region_instance_group_manager.app.name} --region=${var.gcp_region}"
}

output "test_lb_command" {
  description = "Command to test zone distribution across 9 requests."
  value       = "for i in $(seq 1 9); do curl -s http://${google_compute_forwarding_rule.app.ip_address} | grep Zone; done"
}
