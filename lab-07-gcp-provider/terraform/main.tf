# Random suffix ensures globally-unique bucket names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
}

# ─── GCS Bucket (primary, us-central1) ────────────────────────────────────────

resource "google_storage_bucket" "main" {
  name          = "${local.name_prefix}-us"
  location      = "US"
  storage_class = "STANDARD"

  # force_destroy = true allows `terraform destroy` to delete the bucket even
  # if it contains objects. Without this, GCP returns a 409 error.
  force_destroy = true

  # uniform_bucket_level_access disables per-object ACLs and enforces IAM-only
  # access control — the current GCP best practice.
  uniform_bucket_level_access = true

  labels = {
    managed_by  = "terraform"
    environment = "lab"
  }
}

# ─── GCS Bucket IAM — grant Storage Object Viewer to a service account ────────

resource "google_storage_bucket_iam_member" "viewer" {
  bucket = google_storage_bucket.main.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.service_account_email}"
}

# ─── GCS Bucket (Europe) — uses the aliased provider ─────────────────────────
# Note the explicit `provider = google.europe` reference.
# This bucket is created via the europe-west1 provider instance.

resource "google_storage_bucket" "europe" {
  provider = google.europe

  name          = "${local.name_prefix}-eu"
  location      = "EU"
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    managed_by  = "terraform"
    environment = "lab"
    region      = "europe"
  }
}

# ─── VPC Network ──────────────────────────────────────────────────────────────
# GCP VPCs are global — a single VPC spans all regions.
# auto_create_subnetworks = false means we manage subnets explicitly (custom mode).

resource "google_compute_network" "main" {
  name                    = "${var.bucket_name_prefix}-vpc"
  auto_create_subnetworks = false
  description             = "Lab 07 VPC — managed by Terraform"
}

# ─── Subnet ───────────────────────────────────────────────────────────────────
# GCP subnets are regional (span all zones within a region).
# An instance in us-central1-a attaches to this us-central1 subnet.

resource "google_compute_subnetwork" "main" {
  name          = "${var.bucket_name_prefix}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# ─── Firewall — allow SSH ─────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.bucket_name_prefix}-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Restrict to your IP in production. "0.0.0.0/0" is acceptable for a lab.
  source_ranges = ["0.0.0.0/0"]

  target_tags = ["tf-lab07-web"]
}

# ─── GCE Instance (e2-micro, us-central1-a, free tier) ───────────────────────

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_compute_instance" "web" {
  name         = "${var.bucket_name_prefix}-web"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  tags = ["tf-lab07-web"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10 # GB — minimum disk size
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id

    # access_config block with no attributes assigns an ephemeral external IP.
    # Omit this block entirely for a private-only instance.
    access_config {}
  }

  metadata = {
    managed_by = "terraform"
    lab        = "07-gcp-provider"
  }

  # Minimal startup script
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    echo "Lab 07 instance ready" > /tmp/lab07.txt
  EOT
}
