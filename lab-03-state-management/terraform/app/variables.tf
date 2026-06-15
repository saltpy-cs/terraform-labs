variable "gcp_project" {
  description = "GCP project ID to deploy resources into."
  type        = string
}

variable "gcp_region" {
  description = "GCP region for resources and the provider."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short name used to prefix all resource names."
  type        = string
  default     = "tf-lab03"
}
