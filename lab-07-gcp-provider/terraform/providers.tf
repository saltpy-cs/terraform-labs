terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Default provider — uses var.gcp_region (default: us-central1)
provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Aliased provider — europe-west1
# Resources that set `provider = google.europe` are created in this region.
# The project is the same; only the region changes.
provider "google" {
  alias   = "europe"
  project = var.gcp_project
  region  = "europe-west1"
}

# http provider — requires no credentials.
# Used to demonstrate that Terraform can manage resources from multiple
# providers in a single configuration, even lightweight ones with no auth.
provider "http" {}
