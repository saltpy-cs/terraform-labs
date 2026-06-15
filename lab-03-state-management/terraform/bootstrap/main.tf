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
}

provider "aws" {
  region = var.aws_region
}

# random_id appends an 8-character hex suffix to guarantee a globally unique
# S3 bucket name. S3 bucket names share a single global namespace across all
# AWS accounts, so collisions on common names are common.
resource "random_id" "suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# S3 bucket — stores the Terraform state files
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = "${var.project_name}-state-${random_id.suffix.hex}"

  # Prevent accidental deletion while state files live inside.
  # Remove this before running terraform destroy at the end of the lab.
  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = {
    Name    = "${var.project_name}-state"
    Purpose = "terraform-state"
    Lab     = "lab-03"
  }
}

# Versioning lets you roll back to a previous state file if something goes
# wrong. Without versioning a bad apply could permanently overwrite state.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest. State files contain sensitive values (passwords,
# private keys, etc.) so encryption is non-optional in production.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access as an extra safety net.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB table — provides state locking
# ---------------------------------------------------------------------------

# DynamoDB is used for distributed locking. Terraform writes a lock item
# before any operation that modifies state and deletes it when done.
# The hash key MUST be named "LockID" — this is what the S3 backend expects.
resource "aws_dynamodb_table" "locks" {
  name         = "${var.project_name}-locks"
  billing_mode = "PAY_PER_REQUEST" # No capacity planning needed; lock ops are infrequent
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "${var.project_name}-locks"
    Purpose = "terraform-state-locking"
    Lab     = "lab-03"
  }
}
