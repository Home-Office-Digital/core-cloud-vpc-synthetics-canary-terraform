
output "canary_name" {
  value = aws_synthetics_canary.vpc_connectivity_check.name
}

output "canary_role_arn" {
  value = aws_iam_role.canary_role.arn
}

output "dest_instance_ids" {
  value = [for ec2 in aws_instance.dest_instance : ec2.id]
}
