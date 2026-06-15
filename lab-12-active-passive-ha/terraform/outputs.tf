output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.primary.name
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name — use with Cloud SQL Auth Proxy: '<connection_name>'"
  value       = google_sql_database_instance.primary.connection_name
}

output "cloud_sql_private_ip" {
  description = "Private IP address of the Cloud SQL primary instance"
  value       = google_sql_database_instance.primary.private_ip_address
}

output "cloud_sql_availability_type" {
  description = "Cloud SQL availability type (REGIONAL = HA, ZONAL = single zone)"
  value       = google_sql_database_instance.primary.settings[0].availability_type
}

output "cloud_sql_db_name" {
  description = "Database name within Cloud SQL"
  value       = google_sql_database.app.name
}

output "cloud_sql_db_user" {
  description = "Database user"
  value       = google_sql_user.app.name
}

output "cloud_sql_db_password" {
  description = "Database password — stored in state; use Secret Manager in production"
  value       = random_password.db.result
  sensitive   = true
}

output "redis_host" {
  description = "Memorystore Redis host — connect via this IP from within the VPC"
  value       = google_redis_instance.primary.host
}

output "redis_port" {
  description = "Memorystore Redis port"
  value       = google_redis_instance.primary.port
}

output "redis_tier" {
  description = "Redis tier (STANDARD_HA = HA with replica, BASIC = no HA)"
  value       = google_redis_instance.primary.tier
}

output "redis_current_location" {
  description = "Current primary zone of the Redis instance"
  value       = google_redis_instance.primary.current_location_id
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "psa_allocated_range" {
  description = "Private Service Access IP range allocated for Cloud SQL and Memorystore"
  value       = "${google_compute_global_address.private_ip_alloc.address}/${google_compute_global_address.private_ip_alloc.prefix_length}"
}

output "inspect_commands" {
  description = "gcloud commands to inspect HA status after apply"
  value       = <<-EOT
    # Check Cloud SQL HA status and current primary zone:
    gcloud sql instances describe ${google_sql_database_instance.primary.name} \
      --project=${var.gcp_project} \
      --format="value(gceZone, secondaryGceZone, settings.availabilityType)"

    # Check Redis current primary zone:
    gcloud redis instances describe ${google_redis_instance.primary.name} \
      --region=${var.gcp_region} \
      --project=${var.gcp_project} \
      --format="value(currentLocationId,persistenceIamIdentity)"

    # Trigger Cloud SQL switchover (run after apply):
    terraform apply -var="failover_timestamp=$(date +%s)"

    # Trigger Redis failover:
    terraform apply -var="redis_failover_timestamp=$(date +%s)"
  EOT
}
