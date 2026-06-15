variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix resource names and tags."
  type        = string
  default     = "tf-lab06"
}

variable "instance_count" {
  description = "Number of identical EC2 instances to create with count. Must be between 1 and 5."
  type        = number
  default     = 3

  validation {
    condition     = var.instance_count > 0 && var.instance_count <= 5
    error_message = "instance_count must be greater than 0 and no more than 5."
  }
}

variable "environments" {
  description = "Map of environment names to configuration. Each entry creates one EC2 instance via for_each."
  type = map(object({
    instance_type = string
    subnet_cidr   = string
  }))
  default = {
    staging = {
      instance_type = "t3.nano"
      subnet_cidr   = "10.0.10.0/24"
    }
    production = {
      instance_type = "t3.nano"
      subnet_cidr   = "10.0.11.0/24"
    }
  }
}

variable "security_group_rules" {
  description = "List of ingress rules to generate in the security group. Used by the dynamic block."
  type = list(object({
    port        = number
    protocol    = string
    description = string
  }))
  default = [
    { port = 80,  protocol = "tcp", description = "HTTP" },
    { port = 443, protocol = "tcp", description = "HTTPS" },
    { port = 22,  protocol = "tcp", description = "SSH" },
  ]
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g. 203.0.113.5/32). Used to scope SSH and HTTP access."
  type        = string
}
