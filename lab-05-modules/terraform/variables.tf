variable "gcp_project" {
  description = "GCP project ID to deploy resources into."
  type        = string
}

variable "gcp_region" {
  description = "GCP region to deploy resources into."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for compute instances."
  type        = string
  default     = "us-central1-a"
}

variable "project_name" {
  description = "Short name used to prefix resource names."
  type        = string
  default     = "tf-lab05"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g. 203.0.113.5/32). Used to scope SSH firewall access."
  type        = string
}
