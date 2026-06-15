terraform {
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

  # ---------------------------------------------------------------------------
  # REMOTE BACKEND CONFIGURATION
  #
  # Fill in the bucket value from the bootstrap output before running
  # `terraform init` in this directory:
  #
  #   terraform -chdir=../bootstrap output bucket_name
  #
  # Then replace REPLACE_WITH_BUCKET_NAME below.
  #
  # Alternative — pass via -backend-config flags at init time (useful in CI):
  #
  #   terraform init \
  #     -backend-config="bucket=tf-lab03-tfstate-a1b2c3d4"
  #
  # GCS locking: unlike the AWS S3 backend (which requires a separate DynamoDB
  # table), the GCS backend provides locking natively using a conditional write
  # on the state object generation. No lock table is needed.
  # ---------------------------------------------------------------------------
  backend "gcs" {
    bucket = "REPLACE_WITH_BUCKET_NAME" # Replace with output from bootstrap: terraform -chdir=../bootstrap output bucket_name
    prefix = "lab03/app"
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# App GCS bucket
#
# A simple GCS bucket representing "application data storage". GCS buckets
# are free at low usage levels — the goal here is to practice state operations,
# not to build real application infrastructure.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "app_data" {
  name     = "${var.project_name}-app-${var.environment}-${random_id.suffix.hex}"
  location = var.gcp_region

  # force_destroy = true allows terraform destroy to delete the bucket even if
  # it contains objects. Safe here because this is a lab bucket.
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }
}
