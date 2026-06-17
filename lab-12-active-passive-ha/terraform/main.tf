terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# ─── Random password ──────────────────────────────────────────────────────────
# The password is stored in Terraform state. For a lab this is acceptable;
# in production use Secret Manager or Vault to keep credentials out of state.

resource "random_password" "db" {
  length  = 24
  special = false
}

# ─── VPC Network ──────────────────────────────────────────────────────────────

resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.project_name}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# ─── Private Service Access (PSA) ─────────────────────────────────────────────
#
# Cloud SQL with a private IP and Memorystore both require Private Service Access.
# PSA establishes a VPC peering connection between your VPC and Google's
# managed services network, so managed instances (Cloud SQL, Redis) get
# internal IPs that are reachable from your subnet without traversing the
# public internet.
#
# Two resources are needed:
# 1. google_compute_global_address  — reserves a CIDR block for Google to
#    assign to managed service instances. /16 is generous; /24 would also work.
# 2. google_service_networking_connection — creates the actual VPC peering to
#    servicenetworking.googleapis.com using that reserved range.
#
# Note: google_service_networking_connection can be slow to create (~2 min)
# and sometimes requires the servicenetworking.googleapis.com API to be
# enabled before apply. See the Setup section in README.md.

resource "google_compute_global_address" "private_ip_alloc" {
  name          = "${var.project_name}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}

# ─── Cloud SQL (PostgreSQL, REGIONAL HA) ──────────────────────────────────────
#
# availability_type = "REGIONAL" provisions:
#   - a PRIMARY instance in one zone (chosen by GCP within the region)
#   - a STANDBY instance in a different zone within the same region
#
# The standby uses synchronous replication: every write is committed to both
# primary and standby before the client receives an acknowledgement. This
# gives RPO ≈ 0 (no committed transactions are lost on failover).
#
# When the primary becomes unavailable, GCP automatically promotes the standby
# to primary (RTO 30s–2min). Connections using the Cloud SQL instance's
# connection name or private IP reconnect automatically after promotion.
#
# Contrast with read replicas (not configured here):
#   - REGIONAL standby:  synchronous, same region, no client access, auto-failover
#   - Read replica:      asynchronous, any region, client-readable, manual promote

resource "google_sql_database_instance" "primary" {
  name             = "${var.project_name}-pg"
  database_version = var.db_version
  region           = var.gcp_region

  # deletion_protection must be false so `terraform destroy` can delete the
  # instance. Cloud SQL defaults this to true; in production, leave it true.
  deletion_protection = false

  settings {
    tier    = var.db_tier
    edition = "ENTERPRISE"

    # REGIONAL = HA with automatic zonal failover.
    # Change to "ZONAL" to see how Terraform handles a downgrade (Exercise 6).
    availability_type = "REGIONAL"

    # Automated backups enable point-in-time recovery — required for REGIONAL HA.
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"

      backup_retention_settings {
        retained_backups = 7
      }
    }

    # Private IP only — no public IP. Requires the PSA connection above.
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 4
      update_track = "stable"
    }
  }

  # Cloud SQL provisioning can take 5–10 minutes. The PSA connection must
  # exist before Cloud SQL can allocate a private IP in your VPC.
  depends_on = [google_service_networking_connection.private_vpc]
}

resource "google_sql_database" "app" {
  name     = "appdb"
  instance = google_sql_database_instance.primary.name
}

resource "google_sql_user" "app" {
  name     = "appuser"
  instance = google_sql_database_instance.primary.name
  password = random_password.db.result
}

# ─── Memorystore Redis (STANDARD_HA) ──────────────────────────────────────────
#
# tier = "STANDARD_HA" provisions:
#   - a PRIMARY node in location_id (var.primary_zone)
#   - a REPLICA node in alternative_location_id (var.secondary_zone)
#
# Replication is asynchronous but the lag is typically sub-millisecond within
# a region. On primary failure, GCP automatically promotes the replica within
# seconds (RTO ~10–30s). The connection endpoint (var.redis_host) stays the
# same — clients reconnect to the new primary transparently.
#
# Contrast with BASIC tier:
#   - No replica, no automatic failover — a failed node means downtime until
#     GCP repairs or replaces it (RTO: minutes to hours)
#   - RPO: all in-memory data is lost (unless persistence is enabled)

resource "google_redis_instance" "primary" {
  name           = "${var.project_name}-redis"
  tier           = "STANDARD_HA"
  memory_size_gb = var.redis_memory_gb
  region         = var.gcp_region

  location_id             = var.primary_zone
  alternative_location_id = var.secondary_zone

  authorized_network = google_compute_network.main.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  # For PRIVATE_SERVICE_ACCESS, reserved_ip_range is the NAME of the
  # google_compute_global_address resource (not the CIDR address).
  reserved_ip_range = google_compute_global_address.private_ip_alloc.name

  redis_version = "REDIS_7_0"

  depends_on = [google_service_networking_connection.private_vpc]
}
