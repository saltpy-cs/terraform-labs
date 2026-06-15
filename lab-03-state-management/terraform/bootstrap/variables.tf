variable "gcp_project" {
  description = "GCP project ID to deploy resources into."
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the provider. The state bucket is multi-regional (US) regardless of this value."
  type        = string
  default     = "us-central1"
}

variable "project_name" {
  description = "Short name used to prefix all resource names."
  type        = string
  default     = "tf-lab03"
}
