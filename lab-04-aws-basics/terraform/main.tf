terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Data source: latest Amazon Linux 2023 AMI
#
# Using a data source rather than a hardcoded AMI ID means this config always
# uses the latest patched image without manual updates. AMI IDs are
# region-specific, so this also avoids hardcoding a region-dependent value.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.project_name
    Lab  = "lab-04"
  }
}

# ---------------------------------------------------------------------------
# Public subnet
#
# map_public_ip_on_launch = true ensures instances launched into this subnet
# automatically receive a public IP. Without this, we would need an Elastic IP.
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id   # implicit dependency on aws_vpc.main
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public"
    Lab  = "lab-04"
  }
}

# ---------------------------------------------------------------------------
# Internet gateway
#
# An IGW is required for any resource in the VPC to have a route to the
# internet. Without it, instances are completely isolated from the internet
# even if they have public IPs.
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id   # implicit dependency on aws_vpc.main

  tags = {
    Name = "${var.project_name}-igw"
    Lab  = "lab-04"
  }
}

# ---------------------------------------------------------------------------
# Route table and association
#
# The route table defines where traffic is routed. The default route (0.0.0.0/0)
# sends all internet-bound traffic to the internet gateway.
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id   # implicit dependency on IGW
  }

  tags = {
    Name = "${var.project_name}-public-rt"
    Lab  = "lab-04"
  }
}

# The association links the route table to the subnet. Without this, the subnet
# uses the VPC's default (local-only) route table and has no internet access.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id       # implicit dependency on subnet
  route_table_id = aws_route_table.public.id  # implicit dependency on route table
}

# ---------------------------------------------------------------------------
# Security group
#
# Restricting SSH to var.my_ip_cidr (your specific IP) is the correct pattern.
# Avoid 0.0.0.0/0 for SSH — it exposes the port to every IP on the internet.
# ---------------------------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow SSH from my IP; allow all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from operator IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
    Lab  = "lab-04"
  }
}

# ---------------------------------------------------------------------------
# EC2 instance
#
# t3.nano is the smallest x86_64 instance type: 2 vCPU, 0.5 GiB RAM, ~$0.0052/hr.
# Sufficient for demonstrating Terraform provider basics.
#
# COST REMINDER: Destroy this lab promptly after completing the exercises.
# ---------------------------------------------------------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id   # implicit dependency on data source
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.public.id            # implicit dependency on subnet
  vpc_security_group_ids = [aws_security_group.web.id]     # implicit dependency on SG

  # Uncomment and set a key pair name if you want to SSH into the instance.
  # Create a key pair first: aws ec2 create-key-pair --key-name tf-lab04 ...
  # key_name = "tf-lab04"

  tags = {
    Name = "${var.project_name}-web"
    Lab  = "lab-04"
  }
}
