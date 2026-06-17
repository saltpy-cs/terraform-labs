# ─── Bastion VM ───────────────────────────────────────────────────────────────
#
# A small VM in the same VPC subnet as Cloud SQL and Redis. Because both
# services use private IPs only, connections must originate from within the
# VPC. The bastion is the jump point for operator access.
#
# postgresql-client and redis-tools are installed at startup so psql and
# redis-cli are available immediately after SSH.

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_name}-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.my_ip_cidr]
  target_tags   = ["bastion"]
}

resource "google_compute_instance" "bastion" {
  name         = "${var.project_name}-bastion"
  machine_type = "e2-micro"
  zone         = var.primary_zone
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.self_link
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y postgresql-client redis-tools
  EOT
}
