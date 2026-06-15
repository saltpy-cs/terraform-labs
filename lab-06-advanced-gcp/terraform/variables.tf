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
  default     = "tf-lab06"
}

variable "web_subnet_cidr" {
  description = "CIDR range for the subnet used by count-based web instances."
  type        = string
  default     = "10.0.0.0/24"
}

variable "instance_count" {
  description = "Number of identical GCE instances to create with count. Must be between 1 and 5."
  type        = number
  default     = 3

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 5
    error_message = "instance_count must be between 1 and 5 inclusive."
  }
}

variable "environments" {
  description = "Map of environment names to configuration. Each entry creates one GCE instance and one subnet via for_each."
  type = map(object({
    machine_type = string
    subnet_cidr  = string
  }))
  default = {
    dev = {
      machine_type = "e2-micro"
      subnet_cidr  = "10.0.1.0/24"
    }
    staging = {
      machine_type = "e2-micro"
      subnet_cidr  = "10.0.2.0/24"
    }
  }
}

variable "firewall_rules" {
  description = "List of allow rules to generate in the combined firewall rule. Used by the dynamic block."
  type = list(object({
    port        = string
    protocol    = string
    description = string
  }))
  default = [
    { port = "22",  protocol = "tcp", description = "SSH" },
    { port = "80",  protocol = "tcp", description = "HTTP" },
    { port = "443", protocol = "tcp", description = "HTTPS" },
  ]
}
