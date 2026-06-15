variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
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
  description = "Per-environment instance configuration"
  type = map(object({
    instance_type = string
    disk_size     = number
    tags          = map(string)
  }))
  default = {
    dev = {
      instance_type = "t3.nano"
      disk_size     = 8
      tags = {
        cost_center = "engineering"
        tier        = "development"
      }
    }
    staging = {
      instance_type = "t3.nano"
      disk_size     = 8
      tags = {
        cost_center = "engineering"
        tier        = "staging"
      }
    }
    prod = {
      instance_type = "t3.nano"
      disk_size     = 10
      tags = {
        cost_center = "operations"
        tier        = "production"
      }
    }
  }
}

variable "allowed_ports" {
  description = "TCP ports to allow in the security group"
  type        = list(number)
  default     = [22, 80, 443]
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g. 1.2.3.4/32). Used to restrict SSH access."
  type        = string
}
