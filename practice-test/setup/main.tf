terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "gcp_project" {
  type        = string
  description = "The GCP project ID to provision resources in."
}

variable "gcp_region" {
  type        = string
  description = "The GCP region for regional resources."
  default     = "us-central1"
}

# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# ---------------------------------------------------------------------------
# Random suffix — keeps bucket names globally unique
# ---------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# GCS bucket for remote state backend (Q3)
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "practice_state" {
  name          = "tf-practice-state-${random_id.suffix.hex}"
  location      = "US-CENTRAL1"
  project       = var.gcp_project
  force_destroy = true

  versioning {
    enabled = true
  }

  labels = {
    purpose = "terraform-practice-test"
    role    = "state-backend"
  }
}

# ---------------------------------------------------------------------------
# GCS bucket for import exercise (Q9)
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "import_target" {
  name          = "tf-practice-import-${random_id.suffix.hex}"
  location      = "US-CENTRAL1"
  project       = var.gcp_project
  force_destroy = true

  labels = {
    purpose = "terraform-practice-test"
    role    = "import-exercise"
  }
}

# ---------------------------------------------------------------------------
# VPC network for data source lookup (Q4)
# ---------------------------------------------------------------------------

resource "google_compute_network" "practice" {
  name                    = "practice-vpc"
  project                 = var.gcp_project
  auto_create_subnetworks = false
}

# ---------------------------------------------------------------------------
# Create working directory tree
# ---------------------------------------------------------------------------

resource "null_resource" "create_dirs" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/tf-practice/q01
      mkdir -p ~/tf-practice/q02
      mkdir -p ~/tf-practice/q03
      mkdir -p ~/tf-practice/q04
      mkdir -p ~/tf-practice/q05/modules/tagger
      mkdir -p ~/tf-practice/q06
      mkdir -p ~/tf-practice/q07
      mkdir -p ~/tf-practice/q08
      mkdir -p ~/tf-practice/q09
      mkdir -p ~/tf-practice/q10
      mkdir -p ~/tf-practice/q11/modules/labeler
      mkdir -p ~/tf-practice/q11/tests
      mkdir -p ~/tf-practice/q12
    EOT
  }
}

# ---------------------------------------------------------------------------
# Write environment information to well-known files
# These files are read by the practice questions at test time.
# ---------------------------------------------------------------------------

resource "null_resource" "write_files" {
  depends_on = [
    google_storage_bucket.practice_state,
    google_storage_bucket.import_target,
    google_compute_network.practice,
    null_resource.create_dirs,
  ]

  triggers = {
    state_bucket  = google_storage_bucket.practice_state.name
    import_bucket = google_storage_bucket.import_target.name
    vpc_self_link = google_compute_network.practice.self_link
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/../q03 ${path.module}/../q04 ${path.module}/../q09
      printf '%s' '${google_storage_bucket.practice_state.name}' > ${path.module}/../q03/bucket-name.txt
      printf '%s' '${google_storage_bucket.import_target.name}' > ${path.module}/../q09/import-bucket.txt
      printf '%s' '${google_compute_network.practice.self_link}' > ${path.module}/../q04/vpc-selflink.txt
    EOT
  }
}

# ---------------------------------------------------------------------------
# Q7 template file
# $${env} and $${project} are HCL escapes for literal ${ in the file content.
# The file written to disk contains: ${env} and ${project} — correct templatefile() syntax.
# ---------------------------------------------------------------------------

resource "local_file" "q07_template" {
  depends_on = [null_resource.create_dirs]

  filename = pathexpand("~/tf-practice/q07/startup.sh.tpl")
  content  = <<-EOT
    #!/bin/bash
    ENV="$${env}"
    PROJECT="$${project}"
    echo "Running $${project} in $${env}"
  EOT
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "state_bucket_name" {
  description = "Name of the GCS bucket to use as the remote state backend (Q3)"
  value       = google_storage_bucket.practice_state.name
}

output "import_bucket_name" {
  description = "Name of the GCS bucket to import in Q9"
  value       = google_storage_bucket.import_target.name
}

output "vpc_self_link" {
  description = "self_link of the practice VPC network (Q4)"
  value       = google_compute_network.practice.self_link
}

output "vpc_name" {
  description = "Name of the practice VPC network"
  value       = google_compute_network.practice.name
}

output "q07_template_path" {
  description = "Path to the startup script template created for Q7"
  value       = pathexpand("~/tf-practice/q07/startup.sh.tpl")
}

output "setup_complete" {
  description = "Summary of files and resources created for the practice test"
  value = {
    state_bucket_file  = "practice-test/q03/bucket-name.txt  (GCS bucket name for Q3 backend)"
    import_bucket_file = "practice-test/q09/import-bucket.txt (GCS bucket name for Q9 import)"
    vpc_selflink_file  = "practice-test/q04/vpc-selflink.txt  (VPC self_link for Q4)"
    q07_template       = "~/tf-practice/q07/startup.sh.tpl"
    work_dirs          = "~/tf-practice/q01 … q12"
  }
}
