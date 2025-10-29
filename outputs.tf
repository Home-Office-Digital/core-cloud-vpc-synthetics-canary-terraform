
output "canary_name" {
  value = aws_synthetics_canary.vpc_connectivity.name
}

output "canary_role_arn" {
  value = aws_iam_role.canary_role.arn
}

