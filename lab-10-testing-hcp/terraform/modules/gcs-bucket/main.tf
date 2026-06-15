resource "google_storage_bucket" "this" {
  name     = var.bucket_name
  project  = var.project
  location = var.location

  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = var.enable_versioning
  }

  labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "terraform"
  })
}
