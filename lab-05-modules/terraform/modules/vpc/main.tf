locals {
  common_tags = merge(
    {
      Module = "vpc"
      Name   = var.vpc_name
    },
    var.tags
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, { Name = var.vpc_name })
}

# for_each creates one subnet per CIDR in the list.
# toset() converts the list to a set so each element can be used as a map key.
# The subnet's key (each.key) is the CIDR string itself.
resource "aws_subnet" "public" {
  for_each = toset(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.key
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "${var.vpc_name}-public-${each.key}" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.vpc_name}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${var.vpc_name}-public-rt" })
}

# One route table association per subnet — mirrors the for_each on aws_subnet.public.
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
