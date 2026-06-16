# Unit tests for the gcs-bucket module.
# Uses mock_provider "google" — no real GCP API calls are made.
# These tests run fast (< 1 second) and cost nothing.

mock_provider "google" {}

# ── Test 1: Versioning enabled ────────────────────────────────────────────────

run "versioning_enabled" {
  command = apply

  module {
    source = "./modules/gcs-bucket"
  }

  variables {
    bucket_name       = "test-bucket-versioning-on"
    project           = "mock-project"
    enable_versioning = true
    environment       = "dev"
    labels            = { test = "true" }
  }

  assert {
    condition     = output.versioning_enabled == true
    error_message = "Expected versioning to be enabled when enable_versioning=true"
  }

  assert {
    condition     = output.bucket_name != ""
    error_message = "bucket_name should not be empty"
  }

  assert {
    condition     = startswith(output.bucket_url, "gs://")
    error_message = "bucket_url should start with 'gs://'"
  }
}

# ── Test 2: Versioning disabled ───────────────────────────────────────────────

run "versioning_disabled" {
  command = apply

  module {
    source = "./modules/gcs-bucket"
  }

  variables {
    bucket_name       = "test-bucket-versioning-off"
    project           = "mock-project"
    enable_versioning = false
    environment       = "staging"
    labels            = {}
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
    source = "./modules/gcs-bucket"
  }

  variables {
    bucket_name = "test-bucket-bad-env"
    project     = "mock-project"
    environment = "invalid"
  }

  expect_failures = [var.environment]
}
