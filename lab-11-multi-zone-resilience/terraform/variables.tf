variable "gcp_project" {
  type        = string
  description = "GCP project ID."
}

variable "gcp_region" {
  type        = string
  description = "GCP region. All zones must be within this region."
  default     = "us-central1"
}

variable "project_name" {
  type        = string
  description = "Prefix applied to every resource name."
  default     = "tf-lab11"
}

variable "zones" {
  type        = list(string)
  description = "Zones across which the regional MIG distributes instances."
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]

  validation {
    condition     = length(var.zones) >= 2
    error_message = "At least two zones are required for multi-zone resilience."
  }
}

variable "machine_type" {
  type        = string
  description = "GCE machine type for application instances."
  default     = "e2-micro"
}

variable "subnet_cidr" {
  type        = string
  description = "IP CIDR range for the subnetwork."
  default     = "10.11.0.0/24"
}

variable "min_replicas" {
  type        = number
  description = "Minimum total instances across all zones."
  default     = 3

  validation {
    condition     = var.min_replicas >= 2
    error_message = "min_replicas must be at least 2 to demonstrate zone resilience."
  }
}

variable "max_replicas" {
  type        = number
  description = "Maximum total instances the autoscaler can create."
  default     = 9
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in CIDR notation (e.g. 1.2.3.4/32). Used to restrict SSH access. Find it with: curl ifconfig.me"
}

variable "state_bucket" {
  type        = string
  description = "GCS bucket name to use for Terraform remote state. Create one first or reuse from lab 03."
}
