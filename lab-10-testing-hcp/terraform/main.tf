terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # ── Part B: HCP Terraform ──────────────────────────────────────────────────
  # Uncomment this block for Part B of the lab.
  # Replace "your-org-name" with your HCP Terraform organisation name.
  # After uncommenting, run: terraform login && terraform init
  #
  # cloud {
  #   organization = "your-org-name"
  #
  #   workspaces {
  #     name = "terraform-labs-lab10"
  #   }
  # }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

module "gcs_bucket" {
  source = "./modules/gcs-bucket"

  bucket_name       = "${var.project_name}-${var.environment}"
  project           = var.gcp_project
  enable_versioning = true
  environment       = var.environment
  labels = {
    project    = var.project_name
    managed_by = "terraform"
  }
}
