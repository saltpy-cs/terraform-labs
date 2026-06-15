output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance. Use this to SSH in."
  value       = aws_instance.web.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.web.id
}

output "ami_id" {
  description = "AMI ID resolved by the aws_ami data source. Shows that data source values are available as outputs."
  value       = data.aws_ami.al2023.id
}
