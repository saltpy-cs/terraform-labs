terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# ─── Debian image ─────────────────────────────────────────────────────────────

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ─── VPC Network ──────────────────────────────────────────────────────────────

resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  description             = "Lab 08 VPC — managed by Terraform"
}

# ─── Subnet ───────────────────────────────────────────────────────────────────

resource "google_compute_subnetwork" "main" {
  name          = "${var.project_name}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# ─── Firewall with dynamic allow block ────────────────────────────────────────
# local.firewall_allow_rules is a list of objects built from var.allowed_ports
# in locals.tf. The dynamic block generates one `allow` block per element.
# This pattern replaces hard-coding individual allow blocks.

resource "google_compute_firewall" "main" {
  name    = "${var.project_name}-fw"
  network = google_compute_network.main.name

  dynamic "allow" {
    for_each = local.firewall_allow_rules
    content {
      protocol = allow.value.protocol
      ports    = [allow.value.port]
    }
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.project_name}-app"]
}

# ─── GCE Instances (one per enabled environment) ──────────────────────────────
# for_each = toset(local.enabled_envs) creates one instance per enabled env.
# each.key is the environment name ("dev", "staging", "prod").
#
# toset() converts the list to a set so that env names (not numeric indices)
# become the for_each keys. This is important: keys are stable across list
# reordering, and they are used as instance addresses in state.
#
# Note: for_each resources cannot use splat syntax ([*]) — see Exercise 7.

resource "google_compute_instance" "app" {
  for_each = toset(local.enabled_envs)

  name = "${var.project_name}-${each.key}"

  # lookup() retrieves a value from a map, returning the default if the key
  # is absent. Here: get the machine_type for this env, fall back to "dev".
  machine_type = lookup(var.instance_config, each.key, var.instance_config["dev"]).machine_type
  zone         = var.gcp_zone

  tags = ["${var.project_name}-app"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = lookup(var.instance_config, each.key, var.instance_config["dev"]).disk_size
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    access_config {}
  }

  # templatefile() reads the template file and substitutes ${env} and ${project}.
  # path.module is the directory of this .tf file (terraform/).
  # The template is at templates/startup.sh.tpl, one level up from terraform/.
  metadata_startup_script = templatefile("${path.module}/../templates/startup.sh.tpl", {
    env     = each.key
    project = var.project_name
  })

  labels = merge(
    local.common_labels,
    lookup(var.instance_config, each.key, var.instance_config["dev"]).labels,
    {
      environment = each.key
    }
  )
}

# ─── Conditional resource (prod-only) ─────────────────────────────────────────
# count = 0 → Terraform creates no instances of this resource.
# count = 1 → Terraform creates exactly one.
# This is the standard Terraform pattern for optional/feature-flagged resources.

resource "google_storage_bucket" "prod_data" {
  count = var.enable_production ? 1 : 0

  name          = "${var.project_name}-prod-data-${substr(md5(var.gcp_project), 0, 8)}"
  location      = "US"
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  labels = merge(local.common_labels, {
    environment = "prod"
  })
}

# ─── Flattened subnets (nested structure demo) ────────────────────────────────
# local.all_subnets is a flat map built from the nested var.vpc_config.
# Each key is "<vpc_name>-subnet-<index>"; each value has vpc_name, cidr, vpc_cidr.
# GCP subnets are free — this demonstrates the flattening pattern at zero cost.

resource "google_compute_subnetwork" "multi" {
  for_each = local.all_subnets

  name          = "${var.project_name}-${each.key}"
  ip_cidr_range = each.value.cidr
  region        = var.gcp_region
  network       = google_compute_network.main.id

  description = "Flattened from vpc_config.${each.value.vpc_name} (parent CIDR: ${each.value.vpc_cidr})"
}

# ─── Debug: print env_map during apply ────────────────────────────────────────
# This null_resource uses a local-exec provisioner to echo local.env_map as JSON.
# Useful for verifying complex locals during development. Remove in production.

resource "null_resource" "debug" {
  triggers = {
    env_map_hash = jsonencode(local.env_map)
  }

  provisioner "local-exec" {
    command = "echo 'env_map: ${jsonencode(local.env_map)}'"
  }
}
