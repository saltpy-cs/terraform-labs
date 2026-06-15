terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# ---------------------------------------------------------------------------
# Data source: latest Debian 12 image
#
# Using a data source rather than a hardcoded image name means this config
# always resolves to the latest patched image in the debian-12 family.
# GCE images are owned by well-known projects (e.g. "debian-cloud") and
# organised into families. The family always points at the newest image.
# ---------------------------------------------------------------------------
data "google_compute_image" "debian" {
  most_recent = true
  family      = "debian-12"
  project     = "debian-cloud"
}

# ---------------------------------------------------------------------------
# VPC network
#
# GCP VPC networks are global — a single network spans all regions. This is
# fundamentally different from AWS, where a VPC is regional.
#
# auto_create_subnetworks = false gives us full control over subnets (custom
# mode VPC). With true (default mode), GCP would create a subnet in every
# region automatically.
# ---------------------------------------------------------------------------
resource "google_compute_network" "main" {
  name                    = "${var.project_name}-network"
  auto_create_subnetworks = false
  description             = "Lab 04 VPC network — custom mode, subnets created explicitly"
}

# ---------------------------------------------------------------------------
# Subnet
#
# Subnets in GCP are regional (unlike the VPC itself which is global).
# A subnet must be associated with a region.
#
# There is no internet gateway resource to create — GCP handles internet
# routing automatically for instances that have an external IP address.
# There are also no route table resources to manage; GCP's default routing
# sends 0.0.0.0/0 traffic to the internet for VMs with public IPs.
# ---------------------------------------------------------------------------
resource "google_compute_subnetwork" "public" {
  name          = "${var.project_name}-public-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.main.id # implicit dependency on VPC
}

# ---------------------------------------------------------------------------
# Firewall rule — allow SSH ingress
#
# In GCP, firewall rules are attached to the VPC network, not to individual
# instances (unlike AWS security groups, which attach to the instance).
# Rules are applied to instances via network tags.
#
# Restricting SSH to var.my_ip_cidr (your specific IP) is the correct pattern.
# Avoid 0.0.0.0/0 for SSH — it exposes port 22 to every IP on the internet.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "allow_ssh" {
  name        = "${var.project_name}-allow-ssh"
  network     = google_compute_network.main.name # implicit dependency on VPC
  description = "Allow SSH from operator IP only"
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.my_ip_cidr]

  # target_tags restricts this rule to instances that have the "ssh-enabled"
  # network tag. Instances without that tag are not affected by this rule.
  target_tags = ["ssh-enabled"]
}

# ---------------------------------------------------------------------------
# Firewall rule — allow all egress
#
# GCP's default egress policy is to allow all outbound traffic. We create
# this rule explicitly to make the intent clear in the configuration.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "allow_egress" {
  name        = "${var.project_name}-allow-egress"
  network     = google_compute_network.main.name
  description = "Allow all outbound traffic"
  direction   = "EGRESS"

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# GCE instance
#
# e2-micro is free-tier eligible in us-central1 (one instance per month).
# It is the smallest e2 machine type: 0.25 vCPU (burstable), 1 GiB RAM.
#
# COST REMINDER: Destroy this lab promptly after completing the exercises.
#
# network_interface with an empty access_config {} block allocates an
# ephemeral external IP address. Removing access_config {} gives the instance
# an internal IP only (no direct internet access without Cloud NAT).
# ---------------------------------------------------------------------------
resource "google_compute_instance" "main" {
  name         = "${var.project_name}-instance"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  # Network tags connect this instance to firewall rules that use target_tags.
  # The "ssh-enabled" tag matches google_compute_firewall.allow_ssh above.
  tags = ["ssh-enabled"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link # implicit dependency on data source
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id # implicit dependency on subnet

    # An empty access_config block allocates an ephemeral public IP.
    # Remove this block to create an instance with no public IP.
    access_config {}
  }
}
