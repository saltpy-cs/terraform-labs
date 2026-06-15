terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Default GCP provider — us-central1
provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Aliased GCP provider — Europe region
# Resources that use this provider must set: provider = google.europe
provider "google" {
  alias   = "europe"
  project = var.gcp_project
  region  = "europe-west1"
  zone    = "europe-west1-b"
}

# AWS provider — declared to demonstrate multi-provider configuration.
# No AWS resources are created in this lab; this shows that Terraform
# initialises all declared providers at `terraform init` time.
provider "aws" {
  region = var.aws_region
}
