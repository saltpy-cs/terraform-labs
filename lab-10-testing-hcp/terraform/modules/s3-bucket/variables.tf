variable "bucket_name" {
  description = "The name of the S3 bucket. Must be globally unique."
  type        = string

  validation {
    condition     = length(var.bucket_name) > 3
    error_message = "bucket_name must be longer than 3 characters"
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must start and end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens"
  }
}

variable "enable_versioning" {
  description = "Enable S3 versioning on the bucket"
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

variable "tags" {
  description = "Tags to apply to the S3 bucket"
  type        = map(string)
  default     = {}
}
