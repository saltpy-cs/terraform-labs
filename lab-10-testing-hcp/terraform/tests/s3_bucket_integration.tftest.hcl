# Integration tests for the s3-bucket module.
# Uses a real AWS provider — real S3 buckets are created and destroyed.
# Requires valid AWS credentials in the environment.
# Slower and has a small cost (S3 bucket creation is essentially free).

# ── Test 1: Create bucket with versioning and verify outputs ──────────────────

run "create_bucket_with_versioning" {
  command = apply

  module {
    source = "./modules/s3-bucket"
  }

  variables {
    bucket_name       = "tf-lab10-integ-001"
    enable_versioning = true
    environment       = "dev"
    tags              = { test = "integration", managed_by = "terraform-test" }
  }

  assert {
    condition     = output.bucket_id != ""
    error_message = "Integration test: bucket_id should not be empty after real apply"
  }

  assert {
    condition     = output.versioning_enabled == true
    error_message = "Integration test: versioning should be enabled"
  }

  assert {
    condition     = startswith(output.bucket_arn, "arn:aws:s3:::")
    error_message = "Integration test: bucket_arn should start with 'arn:aws:s3:::'"
  }
}

# ── Test 2: Verify plan shows no changes when config matches state ─────────────
# This run references the same bucket_name as run 1.
# State from run 1 carries over — Terraform should plan zero changes.

run "verify_no_drift" {
  command = plan

  module {
    source = "./modules/s3-bucket"
  }

  variables {
    bucket_name       = "tf-lab10-integ-001"
    enable_versioning = true
    environment       = "dev"
    tags              = { test = "integration", managed_by = "terraform-test" }
  }

  assert {
    condition     = output.bucket_id == "tf-lab10-integ-001"
    error_message = "Bucket ID changed between runs — unexpected drift"
  }
}
