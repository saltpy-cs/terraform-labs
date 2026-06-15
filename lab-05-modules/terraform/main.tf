terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Lab       = "05-modules"
      ManagedBy = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Module sources: local vs registry
#
# LOCAL:    source = "./modules/vpc"
#   - Path is relative to the root configuration directory.
#   - No version pinning (you control the source).
#   - Good for sharing code within a single repository.
#
# REGISTRY: source = "terraform-aws-modules/vpc/aws"
#   - Downloaded from registry.terraform.io on `terraform init`.
#   - Always pin with `version = "~> 5.0"` to avoid unintended upgrades.
#   - Good for battle-tested community modules.
# ---------------------------------------------------------------------------

# Call our local VPC module.
# All inputs defined in modules/vpc/variables.tf must be passed here (except
# those with defaults). The module's outputs are accessed as module.vpc.<output>.
module "vpc" {
  source = "./modules/vpc"

  vpc_name            = "${var.project_name}-vpc"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  enable_dns_hostnames = true

  tags = {
    Environment = "lab"
  }
}

# ---------------------------------------------------------------------------
# Exercise 7: Registry module (comment this block in for the exercise, then
# comment it back out before continuing to avoid extra cost and time).
#
# module "vpc_registry" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "~> 5.0"
#
#   name = "${var.project_name}-registry-vpc"
#   cidr = "10.1.0.0/16"
#
#   azs            = ["${var.aws_region}a"]
#   public_subnets = ["10.1.1.0/24"]
# }
# ---------------------------------------------------------------------------

# Latest Amazon Linux 2023 AMI.
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

# Security group referencing the VPC via module output.
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow SSH from my IP"
  # module.vpc.vpc_id consumes the vpc_id output declared in modules/vpc/outputs.tf.
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

# EC2 instance placed in the first public subnet from the module.
# module.vpc.public_subnet_ids is a list — [0] selects the first element.
resource "aws_instance" "web" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.nano"

  subnet_id                   = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-web"
  }
}
