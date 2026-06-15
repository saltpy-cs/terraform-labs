terraform {
  required_version = ">= 1.6"

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
    tags = local.common_tags
  }
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-subnet"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ─── Security Group with dynamic ingress rules ────────────────────────────────
# The dynamic block iterates over local.security_group_rules (built in locals.tf
# using a for expression over var.allowed_ports).

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Security group for lab 08 instances"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = local.security_group_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ─── AMI data source ──────────────────────────────────────────────────────────

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

# ─── EC2 Instances ────────────────────────────────────────────────────────────
# for_each = toset(local.enabled_envs) creates one instance per enabled environment.
# each.key is the environment name ("dev", "staging", "prod").
#
# Note: toset() is required because for_each on a list would use numeric indices
# as keys. toset() converts the list to a set, using the values as keys.

resource "aws_instance" "app" {
  for_each = toset(local.enabled_envs)

  # lookup() safely retrieves a value from a map, returning the default if the
  # key is not found. Here: get the instance_type for this env, fall back to dev.
  ami           = data.aws_ami.al2023.id
  instance_type = lookup(var.instance_config, each.key, var.instance_config["dev"]).instance_type
  subnet_id     = aws_subnet.main.id

  vpc_security_group_ids = [aws_security_group.app.id]

  # templatefile() reads the template file and substitutes variables.
  # path.module is the directory containing this .tf file.
  user_data = templatefile("${path.module}/../templates/userdata.sh.tpl", {
    env     = each.key
    project = var.project_name
  })

  root_block_device {
    volume_size = lookup(var.instance_config, each.key, var.instance_config["dev"]).disk_size
  }

  tags = merge(
    lookup(var.instance_config, each.key, var.instance_config["dev"]).tags,
    {
      Name        = "${var.project_name}-${each.key}"
      environment = each.key
    }
  )
}

# ─── Conditional resource (prod-only) ─────────────────────────────────────────
# count = 0 means Terraform creates no instances of this resource.
# count = 1 means Terraform creates exactly one.
# This is the standard pattern for optional/conditional resources.

resource "aws_ssm_parameter" "prod_config" {
  count = var.enable_production ? 1 : 0

  name  = "/${var.project_name}/prod/enabled"
  type  = "String"
  value = "true"

  tags = {
    Name        = "${var.project_name}-prod-config"
    environment = "prod"
  }
}

# ─── Debug: echo the env_map local value during apply ─────────────────────────
# This null_resource uses a local-exec provisioner to print local.env_map
# as JSON. Useful for verifying complex locals during development.
# Remove this in production configurations.

resource "null_resource" "debug" {
  triggers = {
    # Re-run when the env_map changes
    env_map_hash = jsonencode(local.env_map)
  }

  provisioner "local-exec" {
    command = "echo 'env_map: ${jsonencode(local.env_map)}'"
  }
}
