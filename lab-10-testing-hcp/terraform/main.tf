terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # ── Part B: HCP Terraform ──────────────────────────────────────────────────
  # Uncomment this block for Part B of the lab.
  # Replace "your-org-name" with your HCP Terraform organisation name.
  # After uncommenting, run: terraform login && terraform init
  #
  # cloud {
  #   organization = "your-org-name"
  #
  #   workspaces {
  #     name = "terraform-labs-lab10"
  #   }
  # }
}

provider "aws" {
  region = var.aws_region
}

module "s3_bucket" {
  source = "./modules/s3-bucket"

  bucket_name        = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  enable_versioning  = true
  environment        = var.environment
  tags = {
    project    = var.project_name
    managed_by = "terraform"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}
