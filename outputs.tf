
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

output "ec2_dns_name" {
  description = "DNS name of the EC2 instance"
  value       = aws_instance.ec2.private_dns
}