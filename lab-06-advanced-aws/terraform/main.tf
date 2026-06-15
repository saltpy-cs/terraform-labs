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
      Lab       = "06-advanced-aws"
      ManagedBy = "terraform"
    }
  }
}

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

# ---------------------------------------------------------------------------
# Networking — minimal VPC, two subnets (one for count, one for for_each)
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

# Subnet for the count-based instances.
resource "aws_subnet" "count_demo" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-count-subnet" }
}

resource "aws_route_table_association" "count_demo" {
  subnet_id      = aws_subnet.count_demo.id
  route_table_id = aws_route_table.public.id
}

# Subnets for the for_each-based instances — one per environment.
# for_each iterates over var.environments so each environment gets its own subnet.
resource "aws_subnet" "foreach_demo" {
  for_each = var.environments

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.subnet_cidr
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-${each.key}-subnet" }
}

resource "aws_route_table_association" "foreach_demo" {
  for_each = aws_subnet.foreach_demo

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security group with a dynamic ingress block
#
# Without dynamic blocks you would write one ingress {} per rule:
#
#   ingress { from_port = 80, to_port = 80, ... }
#   ingress { from_port = 443, to_port = 443, ... }
#   ingress { from_port = 22, to_port = 22, ... }
#
# With dynamic blocks you drive the repetition from a variable.
# Add a new entry to var.security_group_rules and Terraform adds the rule.
# ---------------------------------------------------------------------------

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web security group — rules driven by dynamic block"
  vpc_id      = aws_vpc.main.id

  # dynamic "<block_type>" generates one nested block per item in for_each.
  # The iterator label (here "rule") is used inside content {} to access each item.
  dynamic "ingress" {
    for_each = var.security_group_rules
    iterator = rule

    content {
      description = rule.value.description
      from_port   = rule.value.port
      to_port     = rule.value.port
      protocol    = rule.value.protocol
      cidr_blocks = [var.my_ip_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# ---------------------------------------------------------------------------
# count-based instances
#
# count = N creates N resources addressed as aws_instance.web[0], [1], [2] ...
# count.index is the zero-based integer for the current instance.
#
# Problem: if you change the list that count is derived from, indices shift.
# For example, if count changes from 3 to 2, instance [2] is destroyed.
# More dangerously, if you derive count from a list and remove the first
# element, Terraform destroys [0] and re-creates [1] as the new [0] — even
# though nothing about [1] actually changed.
#
# Use count when instances are truly identical (e.g., a pool of identical
# workers). Use for_each when instances are distinct in any way.
# ---------------------------------------------------------------------------

resource "aws_instance" "web" {
  count = var.instance_count

  ami           = data.aws_ami.al2023.id
  instance_type = "t3.nano"

  subnet_id              = aws_subnet.count_demo.id
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    # count.index gives the zero-based index of this instance in the group.
    Name  = "${var.project_name}-web-${count.index}"
    Index = tostring(count.index)
  }

  lifecycle {
    # create_before_destroy: when this instance must be replaced (e.g. AMI change),
    # Terraform creates the new instance first, then destroys the old one.
    # Without this, Terraform destroys first — causing downtime.
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# for_each-based instances
#
# for_each = <map or set> creates one resource per key, addressed as
# aws_instance.env["staging"], aws_instance.env["production"].
#
# each.key   = the map key (e.g. "staging")
# each.value = the map value (e.g. { instance_type = "t3.nano", subnet_cidr = "..." })
#
# Removing "staging" from the map destroys only aws_instance.env["staging"].
# "production" is untouched. No re-indexing, no surprise recreations.
# ---------------------------------------------------------------------------

resource "aws_instance" "env" {
  for_each = var.environments

  ami           = data.aws_ami.al2023.id
  instance_type = each.value.instance_type

  subnet_id              = aws_subnet.foreach_demo[each.key].id
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = each.key
  }

  lifecycle {
    # ignore_changes tells Terraform to never modify these attributes after
    # initial creation, even if the real resource drifts from the config.
    #
    # Use case: an external system (e.g. a deployment pipeline) writes a
    # "LastModified" tag on every deploy. Without ignore_changes, Terraform
    # would try to remove that tag on every plan because it wasn't in config.
    # With ignore_changes, Terraform records the drift but does not act on it.
    #
    # Exercise 6: comment this out and re-plan after manually adding the tag
    # in the AWS Console to see the difference in plan output.
    ignore_changes = [tags["LastModified"]]
  }
}
