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

# Latest Debian 12 image from the debian-cloud project.
data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ---------------------------------------------------------------------------
# Networking — single custom-mode VPC, subnets created per environment
# ---------------------------------------------------------------------------

resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  project                 = var.gcp_project
  auto_create_subnetworks = false

  # Exercise 5: add a lifecycle block here to demonstrate prevent_destroy.
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# Subnets for the for_each-based instances — one per environment.
# for_each iterates over var.environments so each environment gets its own subnet.
resource "google_compute_subnetwork" "env" {
  for_each = var.environments

  name          = "${var.project_name}-${each.key}-subnet"
  project       = var.gcp_project
  region        = var.gcp_region
  network       = google_compute_network.main.id
  ip_cidr_range = each.value.subnet_cidr
}

# ---------------------------------------------------------------------------
# Firewall rule with a dynamic allow block
#
# Without dynamic blocks you would write one allow {} per rule:
#
#   allow { protocol = "tcp"; ports = ["22"] }
#   allow { protocol = "tcp"; ports = ["80"] }
#   allow { protocol = "tcp"; ports = ["443"] }
#
# With a dynamic block you drive the repetition from a variable.
# Add a new entry to var.firewall_rules and Terraform adds a new allow block.
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "combined" {
  name    = "${var.project_name}-combined"
  project = var.gcp_project
  network = google_compute_network.main.name

  # dynamic "<block_type>" generates one nested block per item in for_each.
  # The iterator label (here "rule") is used inside content {} to access each item.
  dynamic "allow" {
    for_each = var.firewall_rules
    iterator = rule

    content {
      protocol = rule.value.protocol
      ports    = [rule.value.port]
    }
  }

  source_ranges = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# count-based instances
#
# count = N creates N resources addressed as:
#   google_compute_instance.web[0]
#   google_compute_instance.web[1]
#   google_compute_instance.web[2]
#
# count.index is the zero-based integer for the current instance.
#
# Problem: if you reduce count or change the list it is derived from, indices
# shift. For example if count changes from 3 to 2, instance [2] is destroyed.
# More dangerously, if you derive count from a list and remove the first
# element, Terraform destroys [0] and re-creates [1] as the new [0] — even
# though nothing about [1] actually changed.
#
# Use count when instances are truly identical. Use for_each when instances
# are distinct in any way.
# ---------------------------------------------------------------------------

resource "google_compute_instance" "web" {
  count = var.instance_count

  name         = "${var.project_name}-web-${count.index}"
  machine_type = "e2-micro"
  zone         = var.gcp_zone
  project      = var.gcp_project

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
    }
  }

  network_interface {
    network = google_compute_network.main.id

    # Assign an ephemeral external IP.
    access_config {}
  }

  # count.index shows up in metadata so you can inspect it on the instance.
  metadata = {
    instance-index = tostring(count.index)
  }

  lifecycle {
    # create_before_destroy: when this instance must be replaced (e.g. image change),
    # Terraform creates the new instance first, then destroys the old one.
    # Without this, Terraform destroys first — causing downtime.
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# for_each-based instances
#
# for_each = <map or set> creates one resource per key, addressed as:
#   google_compute_instance.env["dev"]
#   google_compute_instance.env["staging"]
#
# each.key   = the map key (e.g. "dev")
# each.value = the map value (e.g. { machine_type = "e2-micro", ... })
#
# Removing "dev" from the map destroys only google_compute_instance.env["dev"].
# "staging" is untouched — no re-indexing, no surprise recreations.
# ---------------------------------------------------------------------------

resource "google_compute_instance" "env" {
  for_each = var.environments

  name         = "${var.project_name}-${each.key}"
  machine_type = each.value.machine_type
  zone         = var.gcp_zone
  project      = var.gcp_project

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.env[each.key].self_link

    access_config {}
  }

  lifecycle {
    # ignore_changes tells Terraform to never modify these metadata keys after
    # initial creation, even if the real instance drifts from the config.
    #
    # Use case: an external system writes a "startup-time" metadata entry on
    # every boot. Without ignore_changes, Terraform would try to remove it on
    # every plan. With ignore_changes, Terraform records the drift but ignores it.
    #
    # Exercise 6: comment this out, then manually add metadata via gcloud and
    # re-run terraform plan to see the difference.
    ignore_changes = [metadata["startup-time"]]
  }
}
