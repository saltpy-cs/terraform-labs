variable "gcp_project" {
  description = "GCP project ID to deploy resources into."
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the subnet and provider default."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for the Compute Engine instance."
  type        = string
  default     = "us-central1-a"
}

variable "project_name" {
  description = "Short name used to prefix all resource names."
  type        = string
  default     = "tf-lab04"
}

variable "subnet_cidr" {
  description = "CIDR range for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "my_ip_cidr" {
  description = "Your public IP address in CIDR notation (e.g. 1.2.3.4/32). Used to restrict SSH access to your machine only. Find your IP: curl ifconfig.me"
  type        = string
}
