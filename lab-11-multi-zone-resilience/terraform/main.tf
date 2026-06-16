terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    prefix = "lab11"
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ── Network ───────────────────────────────────────────────────────────────────

resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.project_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# ── Firewall ──────────────────────────────────────────────────────────────────

# Allow HTTP from any source — LB passes through client IPs (not proxy),
# so the instances see real client IPs and must accept from 0.0.0.0/0.
resource "google_compute_firewall" "allow_http" {
  name    = "${var.project_name}-allow-http"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

# GCP health checker IP ranges — required for LB health checks and MIG auto-healing.
# Without this rule, health checks fail and all instances appear unhealthy.
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.project_name}-allow-hc"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["http-server"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_name}-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.my_ip_cidr]
  target_tags   = ["http-server"]
}

# ── Instance Template ─────────────────────────────────────────────────────────

resource "google_compute_instance_template" "app" {
  # name_prefix + create_before_destroy: each template update produces a new template,
  # old one is deleted after the MIG finishes its rolling update.
  name_prefix  = "${var.project_name}-tpl-"
  machine_type = var.machine_type
  region       = var.gcp_region
  tags         = ["http-server"]

  disk {
    source_image = data.google_compute_image.debian.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
    disk_type    = "pd-balanced"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.self_link
    # access_config with no arguments assigns an ephemeral public IP.
    # Instances need outbound internet access to run apt-get during startup.
    access_config {}
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh.tpl", {
    project_name = var.project_name
  })

  lifecycle {
    # Template updates must create the new template before destroying the old one
    # so the MIG can reference the new template during rolling updates.
    create_before_destroy = true
  }

  labels = {
    version = "v2"
  }
}

# ── Health Check ─────────────────────────────────────────────────────────────

# Regional health check — required by regional NLB and reused for MIG auto-healing.
resource "google_compute_region_health_check" "app" {
  name   = "${var.project_name}-hc"
  region = var.gcp_region

  http_health_check {
    port         = 80
    request_path = "/health"
  }

  # How quickly to consider a newly started instance healthy.
  # Set slightly above the time your startup script takes.
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# ── Regional Managed Instance Group ──────────────────────────────────────────

resource "google_compute_region_instance_group_manager" "app" {
  name               = "${var.project_name}-mig"
  base_instance_name = var.project_name
  region             = var.gcp_region

  # Explicitly pin which zones to use. Omitting this lets GCP choose,
  # but explicit zones make the distribution visible in plans.
  distribution_policy_zones = var.zones

  version {
    instance_template = google_compute_instance_template.app.id
  }

  target_size = var.min_replicas

  named_port {
    name = "http"
    port = 80
  }

  # Auto-healing: when an instance fails the health check, replace it.
  # initial_delay_sec gives instances time to finish the startup script
  # before health checks begin — prevents premature replacement.
  auto_healing_policies {
    health_check      = google_compute_region_health_check.app.id
    initial_delay_sec = 300
  }

  # Rolling update policy: replace instances one at a time with zero
  # downtime. max_unavailable_fixed = 0 means the MIG creates the
  # replacement before removing the old instance.
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = length(var.zones)
    max_unavailable_fixed = 0
  }
}

# ── Autoscaler ───────────────────────────────────────────────────────────────

resource "google_compute_region_autoscaler" "app" {
  name   = "${var.project_name}-autoscaler"
  region = var.gcp_region
  target = google_compute_region_instance_group_manager.app.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

# ── External Network Load Balancer ────────────────────────────────────────────
#
# Architecture:
#   Client → Forwarding Rule (external IP:80) → Regional Backend Service → MIG
#
# This is a passthrough (non-proxy) NLB: the backend instances see the
# original client IP directly. GCP does not terminate the TCP connection.

resource "google_compute_region_backend_service" "app" {
  name                            = "${var.project_name}-backend"
  region                          = var.gcp_region
  protocol                        = "TCP"
  load_balancing_scheme           = "EXTERNAL"
  health_checks                   = [google_compute_region_health_check.app.id]
  connection_draining_timeout_sec = 0

  backend {
    group          = google_compute_region_instance_group_manager.app.instance_group
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "app" {
  name                  = "${var.project_name}-lb"
  region                = var.gcp_region
  backend_service       = google_compute_region_backend_service.app.id
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "80"
}

# ── Resilient State Storage ───────────────────────────────────────────────────
#
# This GCS bucket represents stateful app data (e.g. uploads, config).
# GCS Standard storage is zone-redundant within a region by default.
# Using location = "US" (multi-region) provides additional resilience.

resource "google_storage_bucket" "app_data" {
  name                        = "${var.project_name}-data-${var.gcp_project}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Retain object versions for 30 days to support data recovery.
  lifecycle_rule {
    action { type = "Delete" }
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
  }
}
