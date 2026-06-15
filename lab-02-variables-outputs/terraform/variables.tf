variable "app_name" {
  type        = string
  description = "Application name. Used as a prefix in all resource names."

  validation {
    condition     = length(var.app_name) >= 3 && length(var.app_name) <= 20
    error_message = "app_name must be between 3 and 20 characters."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "replica_count" {
  type        = number
  description = "Number of application replicas."
  default     = 2

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 10
    error_message = "replica_count must be between 1 and 10."
  }
}

variable "enable_monitoring" {
  type        = bool
  description = "Whether to enable monitoring resources."
  default     = false
}

variable "allowed_regions" {
  type        = list(string)
  description = "AWS regions this application may be deployed to."
  default     = ["us-east-1", "eu-west-1", "ap-southeast-1"]
}

variable "instance_types" {
  type        = map(string)
  description = "EC2 instance type per environment."
  default = {
    dev     = "t3.nano"
    staging = "t3.small"
    prod    = "t3.medium"
  }
}

variable "service_config" {
  type = object({
    port     = number
    protocol = string
    timeout  = number
  })
  description = "Service network configuration."
  default = {
    port     = 8080
    protocol = "HTTP"
    timeout  = 30
  }

  validation {
    condition     = var.service_config.port > 0 && var.service_config.port < 65536
    error_message = "service_config.port must be between 1 and 65535."
  }
}

variable "mock_secret" {
  type        = string
  description = "A mock secret value — demonstrates sensitive variables."
  sensitive   = true
  default     = "s3cr3t-d0-n0t-sh0w"
}
