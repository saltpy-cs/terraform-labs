variable "gcp_project" {
  description = "GCP project ID for all resources"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for compute instances"
  type        = string
  default     = "us-central1-a"
}

variable "project_name" {
  description = "Project name prefix for all resource names"
  type        = string
  default     = "tf-lab09"
}

