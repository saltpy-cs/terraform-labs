# Unit tests for the s3-bucket module.
# Uses mock_provider "aws" — no real AWS API calls are made.
# These tests run fast (< 1 second) and cost nothing.

mock_provider "aws" {}

# ── Test 1: Versioning enabled ────────────────────────────────────────────────

run "versioning_enabled" {
  command = apply

  module {
    source = "./modules/s3-bucket"
  }

  variables {
    bucket_name       = "test-bucket-versioning-on"
    enable_versioning = true
    environment       = "dev"
    tags              = { test = "true" }
  }

  assert {
    condition     = output.versioning_enabled == true
    error_message = "Expected versioning to be enabled when enable_versioning=true"
  }

  assert {
    condition     = output.bucket_id != ""
    error_message = "bucket_id should not be empty"
  }
}

# ── Test 2: Versioning disabled ───────────────────────────────────────────────

run "versioning_disabled" {
  command = apply

  module {
    source = "./modules/s3-bucket"
  }

  variables {
    bucket_name       = "test-bucket-versioning-off"
    enable_versioning = false
    environment       = "staging"
    tags              = {}
  }

  assert {
    condition     = output.versioning_enabled == false
    error_message = "Expected versioning to be disabled when enable_versioning=false"
  }
}

# ── Test 3: Variable validation rejects invalid environment ───────────────────
# expect_failures declares that this run block is expected to fail due to
# the validation rule on var.environment.
# If the plan succeeds (validation does NOT trigger), the test itself fails.

run "invalid_environment_rejected" {
  command = plan

  module {
    source = "./modules/s3-bucket"
  }

  variables {
    bucket_name = "test-bucket-bad-env"
    environment = "invalid"
  }

  expect_failures = [var.environment]
}
