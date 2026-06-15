variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resource names"
  type        = string
  default     = "tf-lab09"
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform state. Create this bucket before running terraform init."
  type        = string
}
