terraform {
  # No backend block here — bootstrap uses local state intentionally.
  # See the README for an explanation of the bootstrapping problem.
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# random_id appends an 8-character hex suffix to guarantee a globally unique
# GCS bucket name. GCS bucket names share a single global namespace across all
# GCP projects, so collisions on common names are common.
resource "random_id" "suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# GCS bucket — stores the Terraform state files
#
# GCS provides state locking natively via conditional writes (a generation
# check on the state object). No separate locking resource (like DynamoDB) is
# needed — this is a key difference from the AWS S3+DynamoDB pattern.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "tf_state" {
  name     = "${var.project_name}-tfstate-${random_id.suffix.hex}"
  location = "US" # Multi-regional; higher availability than a single region

  # Prevent Terraform from deleting the bucket (and all state files inside it)
  # if someone accidentally runs terraform destroy on the bootstrap config.
  force_destroy = false

  # Uniform bucket-level access disables per-object ACLs and enforces IAM
  # for all access control. This is the recommended setting for new buckets.
  uniform_bucket_level_access = true

  versioning {
    enabled = true # Enables rolling back to a previous state file if needed
  }

  # Delete non-current (old) versions after 30 days to control storage costs.
  # Non-current versions are older copies kept by versioning after an overwrite.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
  }
}
