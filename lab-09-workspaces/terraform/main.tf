terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # GCS backend for remote state with workspace support.
  #
  # IMPORTANT: Before running `terraform init`, replace YOUR_STATE_BUCKET_NAME
  # with your actual GCS bucket name. You can reuse a bucket from Lab 03, or
  # create a new one:
  #   gsutil mb -l us-central1 gs://YOUR_BUCKET_NAME
  #
  # Workspace state paths in GCS (note: different from S3's env:/ prefix):
  #   default workspace:  gs://<bucket>/lab09/default.tfstate
  #   other workspaces:   gs://<bucket>/lab09/<workspace>/default.tfstate
  #
  # The GCS backend uses the prefix as a directory and stores each workspace
  # state under <prefix>/<workspace>/default.tfstate. Terraform manages this
  # routing automatically — you only configure the prefix once.
  backend "gcs" {
    bucket = "YOUR_STATE_BUCKET_NAME"
    prefix = "lab09"
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

locals {
  # Treat the "default" workspace as "dev" for naming purposes.
  # The "default" workspace always exists and cannot be renamed.
  env = terraform.workspace == "default" ? "dev" : terraform.workspace

  # Per-workspace machine type mapping.
  # lookup(map, key, default) returns the value for the current workspace,
  # falling back to "e2-micro" for any workspace not in the map.
  machine_types = {
    dev     = "e2-micro"
    staging = "e2-micro"
    prod    = "e2-small"
  }
  machine_type = lookup(local.machine_types, local.env, "e2-micro")

  # Name prefix incorporates the workspace name so resources are identifiable.
  name_prefix = "${var.project_name}-${local.env}"
}

# ─── Debian 12 image ──────────────────────────────────────────────────────────

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

resource "google_compute_network" "main" {
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${local.name_prefix}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.name_prefix}-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${local.name_prefix}-instance"]

  description = "Allow SSH for lab 09 instances (workspace: ${terraform.workspace})"
}

# ─── Compute Instance ─────────────────────────────────────────────────────────
# machine_type varies by workspace via local.machine_type (lookup).
# Name incorporates the workspace via local.name_prefix.

resource "google_compute_instance" "app" {
  name         = "${local.name_prefix}-instance"
  machine_type = local.machine_type
  zone         = var.gcp_zone

  tags = ["${local.name_prefix}-instance"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id

    access_config {
      # Ephemeral public IP
    }
  }

  labels = {
    environment = local.env
    workspace   = terraform.workspace
    managed_by  = "terraform"
    lab         = "09-workspaces"
  }
}
