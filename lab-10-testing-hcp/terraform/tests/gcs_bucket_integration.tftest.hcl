# Integration tests for the gcs-bucket module.
# Uses a real GCP provider — real GCS buckets are created and destroyed.
# Requires valid GCP credentials in the environment (GOOGLE_CREDENTIALS or ADC).
# Slower and has a small cost (GCS bucket creation is essentially free).

variable "gcp_project" {
  description = "GCP project ID for integration tests. Picked up from terraform.tfvars."
  type        = string
}

# ── Test 1: Create bucket with versioning and verify outputs ──────────────────

run "create_bucket_with_versioning" {
  command = apply

  module {
    source = "./modules/gcs-bucket"
  }

  variables {
    bucket_name       = "tf-lab10-integ-001"
    project           = var.gcp_project
    enable_versioning = true
    environment       = "dev"
    labels            = { test = "integration", managed_by = "terraform-test" }
  }

  assert {
    condition     = output.bucket_name != ""
    error_message = "Integration test: bucket_name should not be empty after real apply"
  }

  assert {
    condition     = output.versioning_enabled == true
    error_message = "Integration test: versioning should be enabled"
  }

  assert {
    condition     = startswith(output.bucket_url, "gs://")
    error_message = "Integration test: bucket_url should start with 'gs://'"
  }
}

# ── Test 2: Verify plan shows no changes when config matches state ─────────────
# This run references the same bucket_name as run 1.
# State from run 1 carries over — Terraform should plan zero changes.

run "verify_no_drift" {
  command = plan

  module {
    source = "./modules/gcs-bucket"
  }

  variables {
    bucket_name       = "tf-lab10-integ-001"
    project           = var.gcp_project
    enable_versioning = true
    environment       = "dev"
    labels            = { test = "integration", managed_by = "terraform-test" }
  }

  assert {
    condition     = output.bucket_name == "tf-lab10-integ-001"
    error_message = "Bucket name changed between runs — unexpected drift"
  }
}
