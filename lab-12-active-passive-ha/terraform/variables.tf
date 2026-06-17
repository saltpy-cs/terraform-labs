variable "gcp_project" {
  description = "Your GCP project ID (e.g. my-project-123456)"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g. 1.2.3.4/32). Restricts SSH to the bastion. Find it with: curl ifconfig.me"
  type        = string
}

variable "gcp_region" {
  description = "GCP region — must support Cloud SQL and Memorystore (us-central1 is safest)"
  type        = string
  default     = "us-central1"
}

variable "primary_zone" {
  description = "Zone hint for Memorystore primary node; Cloud SQL chooses its own zone"
  type        = string
  default     = "us-central1-a"
}

variable "secondary_zone" {
  description = "Zone for Memorystore HA standby node (must differ from primary_zone)"
  type        = string
  default     = "us-central1-b"
}

variable "project_name" {
  description = "Prefix for all resource names (keep short, lowercase, hyphen-separated)"
  type        = string
  default     = "tf-lab12"
}

variable "db_tier" {
  description = <<-EOT
    Cloud SQL machine tier. db-f1-micro is the cheapest shared-core tier,
    compatible with ENTERPRISE edition. REGIONAL (HA) costs roughly 2× the
    tier price — ~$0.02/hr for db-f1-micro.
  EOT
  type    = string
  default = "db-f1-micro"
}

variable "db_version" {
  description = "Cloud SQL database version"
  type        = string
  default     = "POSTGRES_16"
}

variable "redis_memory_gb" {
  description = "Memorystore Redis capacity in GB (minimum 1). STANDARD_HA costs ~$0.098/hr for 1GB."
  type        = number
  default     = 1
}

# ─── Failover triggers ─────────────────────────────────────────────────────────
#
# Terraform manages desired STATE, not operational EVENTS. A planned switchover
# (moving primary to a different zone) is an event, not a state transition.
#
# The null_resource + local-exec pattern below is a pragmatic workaround that
# lets you trigger a switchover from within `terraform apply`. Understand the
# trade-offs before using this in production — see failover.tf for details.
#
# Usage:
#   terraform apply -var="failover_timestamp=$(date +%s)"
#
# The timestamp changes the triggers map, forcing Terraform to replace the
# null_resource and re-run the provisioner. An empty string means "no failover".

variable "failover_timestamp" {
  description = "Set to $(date +%s) to trigger a Cloud SQL planned switchover. Empty = no switchover."
  type        = string
  default     = ""
}

variable "redis_failover_timestamp" {
  description = "Set to $(date +%s) to trigger a Memorystore Redis failover. Empty = no failover."
  type        = string
  default     = ""
}

variable "redis_data_protection_mode" {
  description = <<-EOT
    Redis failover data protection mode:
    - "limited-data-loss": waits until replica is fully synced (lower data loss, slower)
    - "force-data-loss":   immediate failover regardless of replication lag (faster, may lose recent writes)
  EOT
  type    = string
  default = "limited-data-loss"

  validation {
    condition     = contains(["limited-data-loss", "force-data-loss"], var.redis_data_protection_mode)
    error_message = "Must be 'limited-data-loss' or 'force-data-loss'."
  }
}
