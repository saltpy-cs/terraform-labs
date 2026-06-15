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
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "tf-lab08"
}

variable "environments" {
  description = "List of environments to provision instances for"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "enable_production" {
  description = "When false, the prod environment is excluded from provisioning"
  type        = bool
  default     = true
}

variable "instance_config" {
  description = "Per-environment instance configuration. All use e2-micro for lab cost."
  type = map(object({
    machine_type = string
    disk_size    = number
    labels       = map(string)
  }))
  default = {
    dev = {
      machine_type = "e2-micro"
      disk_size    = 10
      labels = {
        cost_center = "engineering"
        tier        = "development"
      }
    }
    staging = {
      machine_type = "e2-micro"
      disk_size    = 10
      labels = {
        cost_center = "engineering"
        tier        = "staging"
      }
    }
    prod = {
      machine_type = "e2-micro"
      disk_size    = 10
      labels = {
        cost_center = "operations"
        tier        = "production"
      }
    }
  }
}

variable "allowed_ports" {
  description = "TCP ports to open in the firewall rule"
  type        = list(string)
  default     = ["22", "80", "443"]
}

variable "vpc_config" {
  description = <<-EOT
    Multi-environment VPC layout. Each entry has a parent CIDR and a list of
    subnet CIDRs. Used to demonstrate nested structure flattening — a map
    of objects containing lists cannot be used directly with for_each, so
    it must first be flattened into a map with unique composite keys.
  EOT
  type = map(object({
    cidr    = string
    subnets = list(string)
  }))
  default = {
    dev = {
      cidr    = "10.20.0.0/16"
      subnets = ["10.20.1.0/24", "10.20.2.0/24"]
    }
    prod = {
      cidr    = "10.30.0.0/16"
      subnets = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
    }
  }
}
