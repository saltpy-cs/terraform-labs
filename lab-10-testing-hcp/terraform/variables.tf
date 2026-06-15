variable "gcp_project" {
  description = "GCP project ID for all resources"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the provider"
  type        = string
  default     = "us-central1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "tf-lab10"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}
