# No provider blocks inside a module.
# The google provider is configured in the root module and passed down
# automatically. Declaring a provider here would break that contract.

resource "google_compute_network" "this" {
  name                    = var.network_name
  project                 = var.project
  auto_create_subnetworks = var.auto_create_subnetworks

  # Exercise 6: add a description input and wire it here.
  # description = var.description
}

resource "google_compute_subnetwork" "this" {
  name          = "${var.network_name}-subnet"
  project       = var.project
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.subnet_cidr
}
