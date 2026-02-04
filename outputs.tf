
output "canary_name" {
  value = aws_synthetics_canary.vpc_connectivity.name
}

output "canary_role_arn" {
  value = aws_iam_role.canary_role.arn
}

output "canary_alert_topic_arn" {
  value = aws_sns_topic.canary_alerts.arn
}

output "slack_forwarder_lambda" {
  value = aws_lambda_function.slack_forwarder.function_name
}

output "instance_id" {
  value = var.create_ec2 ? aws_instance.this[0].id : null
}

output "security_group_id" {
  value = var.create_ec2 ? aws_security_group.this[0].id : null
}
output "ec2_private_dns_name" {
  description = "Private DNS name of the EC2 instance"
  value       = var.create_ec2 ? aws_instance.this[0].private_dns : ""
}