variable "bucket_name" {
  description = "The name of the GCS bucket. Must be globally unique."
  type        = string

  validation {
    condition     = length(var.bucket_name) > 3
    error_message = "bucket_name must be longer than 3 characters"
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must start and end with a lowercase letter or digit, and contain only lowercase letters, digits, hyphens, and underscores"
  }
}

variable "project" {
  description = "GCP project ID that will own this bucket"
  type        = string
}

variable "location" {
  description = "GCS bucket location. Use a multi-region (US, EU, ASIA) or a specific region (us-central1, europe-west1, etc.)"
  type        = string
  default     = "US"

  validation {
    condition = contains(
      ["US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "europe-west1", "europe-west4", "asia-east1", "asia-southeast1"],
      var.location
    )
    error_message = "location must be one of: US, EU, ASIA, us-central1, us-east1, us-west1, europe-west1, europe-west4, asia-east1, asia-southeast1"
  }
}

variable "enable_versioning" {
  description = "Enable object versioning on the bucket"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Deployment environment. Must be one of: dev, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "labels" {
  description = "Labels to apply to the GCS bucket"
  type        = map(string)
  default     = {}
}
