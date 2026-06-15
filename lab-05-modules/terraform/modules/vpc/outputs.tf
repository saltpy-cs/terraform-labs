output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs for the public subnets created by this module."
  # aws_subnet.public is a map (keyed by CIDR). values() extracts the resource objects,
  # then [*].id extracts the id attribute from each.
  value = [for subnet in aws_subnet.public : subnet.id]
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway."
  value       = aws_internet_gateway.this.id
}
