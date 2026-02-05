terraform {
  backend "s3" {}
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_instance_profile" "ssm_profile" {
  name = var.instance_profile_name
}

resource "aws_security_group" "this" {
  count       = var.create_ec2 ? 1 : 0
  name        = var.security_group_name
  description = "SG for SSM-managed EC2 instance (no ingress by default)"
  vpc_id      = var.dest_vpc_id

  tags = merge(var.tags, { Name = var.security_group_name })
}

resource "aws_security_group_rule" "ingress" {
  for_each = var.create_ec2 ? {
    for idx, r in var.ingress_rules : tostring(idx) => r
  } : {}

  type              = "ingress"
  security_group_id = aws_security_group.this[0].id

  description = try(each.value.description, null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

resource "aws_security_group_rule" "egress" {
  for_each = var.create_ec2 ? {
    for idx, r in var.egress_rules : tostring(idx) => r
  } : {}

  type              = "egress"
  security_group_id = aws_security_group.this[0].id

  description = try(each.value.description, null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

resource "aws_instance" "this" {
  count         = var.create_ec2 ? 1 : 0
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  subnet_id     = var.dest_subnet_id

  vpc_security_group_ids = [aws_security_group.this[0].id]

  iam_instance_profile        = data.aws_iam_instance_profile.ssm_profile.name
  monitoring                  = true
  ebs_optimized               = true
  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  user_data = <<EOF
#!/bin/bash
set -e
systemctl enable amazon-ssm-agent || true
systemctl restart amazon-ssm-agent || true
EOF

  tags = merge(var.tags, { Name = var.instance_name })
}