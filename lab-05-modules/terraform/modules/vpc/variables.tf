variable "vpc_name" {
  description = "Name of the VPC. Used in resource tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets. One subnet is created per entry."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "enable_dns_hostnames" {
  description = "Whether to enable DNS hostnames on the VPC. Required for public EC2 DNS names."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
