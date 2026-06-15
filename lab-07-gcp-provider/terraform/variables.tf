variable "gcp_project" {
  description = "Your GCP project ID (e.g. my-project-123456)"
  type        = string
}

variable "gcp_region" {
  description = "Default GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "Default GCP zone for zonal resources such as GCE instances"
  type        = string
  default     = "us-central1-a"
}

variable "aws_region" {
  description = "AWS region (provider is declared but no resources are created)"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for GCS bucket names. A random suffix is appended to ensure uniqueness."
  type        = string
  default     = "tf-lab07"
}

variable "service_account_email" {
  description = "A GCP service account email to grant Storage Object Viewer on the primary bucket (e.g. mysa@project.iam.gserviceaccount.com)"
  type        = string
}
