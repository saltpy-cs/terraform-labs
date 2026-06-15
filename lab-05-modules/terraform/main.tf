terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
  # Authentication via Application Default Credentials (ADC).
  # Run: gcloud auth application-default login
}

# ---------------------------------------------------------------------------
# Module sources: local vs registry
#
# LOCAL:    source = "./modules/vpc"
#   - Path is relative to the root configuration directory.
#   - No version pinning (you control the source).
#   - Good for sharing code within a single repository.
#
# REGISTRY: source = "terraform-google-modules/network/google"
#   - Downloaded from registry.terraform.io on `terraform init`.
#   - Always pin with `version = "~> 9.0"` to avoid unintended upgrades.
#   - Good for battle-tested community modules.
# ---------------------------------------------------------------------------

# Call our local VPC module.
# All inputs defined in modules/vpc/variables.tf must be passed here (except
# those with defaults). The module's outputs are accessed as module.vpc.<output>.
module "vpc" {
  source = "./modules/vpc"

  network_name            = "${var.project_name}-vpc"
  project                 = var.gcp_project
  region                  = var.gcp_region
  subnet_cidr             = "10.0.0.0/24"
  auto_create_subnetworks = false

  tags = {
    environment = "lab"
  }
}

# ---------------------------------------------------------------------------
# Exercise 8 — Registry module (comment this block in for the exercise, then
# comment it back out before continuing).
#
# module "vpc_registry" {
#   source  = "terraform-google-modules/network/google"
#   version = "~> 9.0"
#
#   project_id   = var.gcp_project
#   network_name = "${var.project_name}-registry-vpc"
#   routing_mode = "GLOBAL"
#
#   subnets = [
#     {
#       subnet_name   = "${var.project_name}-registry-subnet"
#       subnet_ip     = "10.1.0.0/24"
#       subnet_region = var.gcp_region
#     }
#   ]
# }
# ---------------------------------------------------------------------------

# Latest Debian 12 image from the debian-cloud project.
data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# Firewall rule allowing SSH from your IP.
# References module.vpc.network_name — consuming a module output.
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_name}-allow-ssh"
  project = var.gcp_project
  network = module.vpc.network_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.my_ip_cidr]
  target_tags   = ["ssh-enabled"]
}

# GCE instance placed in the subnet from the module.
# module.vpc.subnet_self_link is a URI — the correct reference for subnetwork.
resource "google_compute_instance" "app" {
  name         = "${var.project_name}-app"
  machine_type = "e2-micro"
  zone         = var.gcp_zone
  project      = var.gcp_project

  tags = ["ssh-enabled"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
    }
  }

  network_interface {
    subnetwork = module.vpc.subnet_self_link

    # Assign an ephemeral external IP so you can SSH in.
    access_config {}
  }
}
