terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # S3 backend for remote state with workspace support.
  #
  # IMPORTANT: Before running `terraform init`, replace YOUR_STATE_BUCKET_NAME
  # with your actual S3 bucket name. You can reuse the bucket from Lab 03, or
  # create a new one:
  #   aws s3 mb s3://tf-lab09-state-$(whoami)
  #
  # Workspace state paths in S3:
  #   default workspace:  s3://<bucket>/lab09/terraform.tfstate
  #   other workspaces:   s3://<bucket>/env:/<workspace>/lab09/terraform.tfstate
  backend "s3" {
    bucket = "YOUR_STATE_BUCKET_NAME"
    key    = "lab09/terraform.tfstate"
    region = "us-east-1"

    # Uncomment to enable state locking (requires a DynamoDB table):
    # dynamodb_table = "terraform-state-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      managed_by = "terraform"
      lab        = "09-workspaces"
      workspace  = terraform.workspace
    }
  }
}

locals {
  # Treat the "default" workspace as "dev" for naming purposes.
  # The "default" workspace always exists and cannot be renamed.
  env = terraform.workspace == "default" ? "dev" : terraform.workspace

  # Per-workspace instance type mapping.
  # lookup(map, key, default) returns the value for terraform.workspace,
  # falling back to "t3.nano" for any workspace not in the map.
  instance_types = {
    dev     = "t3.nano"
    staging = "t3.nano"
    prod    = "t3.small"
  }
  instance_type = lookup(local.instance_types, terraform.workspace, "t3.nano")

  # Name prefix incorporates the workspace name so resources are identifiable.
  name_prefix = "${var.project_name}-${local.env}"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${local.name_prefix}-vpc"
    environment = local.env
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "${local.name_prefix}-subnet"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-rt"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg"
  description = "Security group for lab 09 instances (workspace: ${terraform.workspace})"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg"
  }
}

# ─── AMI ──────────────────────────────────────────────────────────────────────

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────
# instance_type varies by workspace via local.instance_type (lookup).
# Name incorporates the workspace via local.name_prefix.

resource "aws_instance" "app" {
  ami           = data.aws_ami.al2023.id
  instance_type = local.instance_type
  subnet_id     = aws_subnet.main.id

  vpc_security_group_ids = [aws_security_group.app.id]

  tags = {
    Name        = "${local.name_prefix}-instance"
    environment = local.env
    workspace   = terraform.workspace
  }
}
