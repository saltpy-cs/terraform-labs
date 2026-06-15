output "vpc_id" {
  description = "ID of the VPC created by the local module."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs from the local module."
  value       = module.vpc.public_subnet_ids
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance."
  value       = aws_instance.web.public_ip
}
