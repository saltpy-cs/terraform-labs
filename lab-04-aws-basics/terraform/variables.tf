variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix resource names and tags."
  type        = string
  default     = "tf-lab04"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    # cidrhost() will error if the value is not a valid CIDR notation.
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "my_ip_cidr" {
  description = <<-EOT
    Your public IP address in CIDR notation (e.g. 1.2.3.4/32).
    Used to restrict SSH access to the EC2 instance to your machine only.
    Find your IP: curl ifconfig.me
  EOT
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0))
    error_message = "my_ip_cidr must be a valid CIDR block (e.g. 1.2.3.4/32)."
  }
}
