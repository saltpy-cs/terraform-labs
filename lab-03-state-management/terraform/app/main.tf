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
  # REMOTE BACKEND — partial configuration
  #
  # The bucket name is intentionally omitted here to avoid committing
  # project-specific values. Pass it at init time:
  #
  #   BUCKET=$(terraform -chdir=../bootstrap output -raw bucket_name)
  #   terraform init -backend-config="bucket=${BUCKET}"
  #
  # GCS locking: unlike the AWS S3 backend (which requires a separate DynamoDB
  # table), the GCS backend provides locking natively using a conditional write
  # on the state object generation. No lock table is needed.
  # ---------------------------------------------------------------------------
  backend "gcs" {
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
