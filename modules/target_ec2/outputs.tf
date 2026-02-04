output "instance_id" {
  value = var.create_ec2 ? aws_instance.this[0].id : null
}

output "ec2_private_dns_name" {
  value = var.create_ec2 ? aws_instance.this[0].private_dns : null
}

output "security_group_id" {
  value = var.create_ec2 ? aws_security_group.this[0].id : null
}
