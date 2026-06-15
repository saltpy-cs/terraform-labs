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

variable "project_name" {
  description = "Short name used as a prefix for all resource names"
  type        = string
  default     = "tf-lab07"
}

variable "your_user_email" {
  description = "Your GCP user account email, for granting IAM access (e.g. you@example.com)"
  type        = string
}
