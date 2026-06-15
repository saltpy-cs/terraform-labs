# Random suffix ensures globally-unique bucket names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
}

# ─── Service Account ──────────────────────────────────────────────────────────
# Service accounts are both a principal (they can be granted roles) and an
# identity (applications authenticate as them, e.g., GCE instances).

resource "google_service_account" "app" {
  account_id   = "${var.project_name}-sa"
  display_name = "Lab 07 Application Service Account"
  description  = "Managed by Terraform — lab-07-gcp-provider"
}

# ─── Project-level IAM (additive) ─────────────────────────────────────────────
# google_project_iam_member is ADDITIVE: it adds one principal:role pair.
# It does not affect any other bindings, including manually-added ones.
# This is the safest approach for project-level IAM in shared environments.

resource "google_project_iam_member" "app_storage_viewer" {
  project = var.gcp_project
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# ─── GCS Bucket (US, default provider) ───────────────────────────────────────

resource "google_storage_bucket" "us" {
  name          = "${local.name_prefix}-us"
  location      = "US"
  storage_class = "STANDARD"

  # force_destroy = true allows `terraform destroy` to delete the bucket even
  # if it contains objects. Without this flag GCP returns a 409 error.
  force_destroy = true

  # uniform_bucket_level_access disables per-object ACLs and enforces IAM-only
  # access — the current GCP best practice.
  uniform_bucket_level_access = true

  labels = {
    managed_by = "terraform"
    lab        = "07"
    region     = "us"
  }
}

# ─── GCS Bucket (Europe, aliased provider) ────────────────────────────────────
# Note the explicit `provider = google.europe`.
# This bucket is created via the europe-west1 provider instance.

resource "google_storage_bucket" "europe" {
  provider = google.europe

  name          = "${local.name_prefix}-eu"
  location      = "EU"
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    managed_by = "terraform"
    lab        = "07"
    region     = "europe"
  }
}

# ─── Resource-level IAM ───────────────────────────────────────────────────────
# Prefer resource-level IAM (e.g., google_storage_bucket_iam_member) over
# project-level IAM when possible — it follows least-privilege more closely.
# Here we grant var.your_user_email Storage Object Viewer on the US bucket only.

resource "google_storage_bucket_iam_member" "user_access" {
  bucket = google_storage_bucket.us.name
  role   = "roles/storage.objectViewer"
  member = "user:${var.your_user_email}"
}

# ─── Service Account Key ──────────────────────────────────────────────────────
# Generates a JSON key for the service account. The private_key output is
# base64-encoded. In production, prefer Workload Identity Federation over SA keys.

resource "google_service_account_key" "app_key" {
  service_account_id = google_service_account.app.name
}

# ─── VPC Network ──────────────────────────────────────────────────────────────
# GCP VPCs are global — a single VPC spans all regions.

resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  description             = "Lab 07 VPC — managed by Terraform"
}

# ─── Subnet ───────────────────────────────────────────────────────────────────

resource "google_compute_subnetwork" "main" {
  name          = "${var.project_name}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# ─── Firewall ─────────────────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_name}-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.project_name}-app"]
}

# ─── Debian image ─────────────────────────────────────────────────────────────

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ─── GCE Instance (e2-micro, free tier) ──────────────────────────────────────
# The service_account block attaches the SA we created above.
# scopes = ["cloud-platform"] grants the instance all roles the SA has — the SA's
# IAM bindings (not the scopes) determine what APIs the instance can actually call.

resource "google_compute_instance" "app" {
  name         = "${var.project_name}-app"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  tags = ["${var.project_name}-app"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    access_config {}
  }

  # Attach the service account so the instance authenticates as google_service_account.app
  service_account {
    email  = google_service_account.app.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    managed_by = "terraform"
    lab        = "07-gcp-provider"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    echo "Lab 07 instance ready" > /tmp/lab07.txt
  EOT
}

# ─── http data source (multi-provider demo, no auth needed) ───────────────────
# The http provider fetches a URL at plan/apply time and returns the response body.
# This demonstrates that a Terraform config can use multiple providers simultaneously.
# Note: only works when Terraform has outbound internet access.

data "http" "metadata" {
  url = "https://ifconfig.me"
}
