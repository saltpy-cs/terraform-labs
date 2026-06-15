terraform {
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

  # ---------------------------------------------------------------------------
  # REMOTE BACKEND CONFIGURATION
  #
  # NOTE: Fill in the bucket and dynamodb_table values from the outputs of the
  # bootstrap/ apply before running `terraform init` in this directory.
  #
  #   cd ../bootstrap && terraform output
  #
  # Then replace REPLACE_WITH_BUCKET_NAME and REPLACE_WITH_TABLE_NAME below.
  #
  # Alternative — use -backend-config flags instead of editing this file:
  #
  #   terraform init \
  #     -backend-config="bucket=tf-lab03-state-a1b2c3d4" \
  #     -backend-config="dynamodb_table=tf-lab03-locks"
  #
  # The -backend-config approach is common in CI/CD pipelines where the bucket
  # name is injected at runtime rather than hardcoded in source control.
  # ---------------------------------------------------------------------------
  backend "s3" {
    bucket         = "REPLACE_WITH_BUCKET_NAME"
    key            = "lab03/app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_TABLE_NAME"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# App S3 bucket
#
# A simple S3 bucket representing "application data storage". We use S3 here
# to keep the lab cost at zero — the goal is to practice state operations,
# not to build real application infrastructure.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "app_data" {
  bucket = "${var.project_name}-app-${var.environment}-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.project_name}-app-${var.environment}"
    Environment = var.environment
    Lab         = "lab-03"
    ManagedBy   = "terraform"
  }
}
