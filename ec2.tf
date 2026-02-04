data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_instance_profile" "ssm_profile" {
  name = var.instance_profile_name
}

# --- Security Group (no ingress by default) ---
resource "aws_security_group" "this" {
  count       = var.create_ec2 ? 1 : 0
  name        = var.security_group_name
  description = "SG for SSM-managed EC2 instance (no ingress by default)"
  vpc_id      = var.dest_vpc_id

  tags = merge(local.tags, {
    Name = var.security_group_name
  })
}

# Ingress rules: NONE by default (var.ingress_rules default = [])
resource "aws_security_group_rule" "ingress" {
  for_each = var.create_ec2 ? {
    for idx, r in var.ingress_rules : tostring(idx) => r
  } : {}
  type              = "ingress"
  security_group_id = aws_security_group.this.id

  description = try(each.value.description, null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

# Egress rules: configure to avoid 0.0.0.0/0 + -1 (Checkov)
resource "aws_security_group_rule" "egress" {
  for_each = var.create_ec2 ? {
    for idx, r in var.egress_rules : tostring(idx) => r
  } : {}

  type              = "egress"
  security_group_id = aws_security_group.this.id

  description = try(each.value.description, null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

resource "aws_instance" "this" {
  count                  = var.create_ec2 ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.dest_subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]

  iam_instance_profile        = data.aws_iam_instance_profile.ssm_profile.name
  monitoring                  = true
  ebs_optimized               = true
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  # EBS encryption explicitly enabled (Checkov)
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  # SSM agent is already on AL2023; keep user_data simple + reliable
  user_data = <<EOF
#!/bin/bash
set -e
systemctl enable amazon-ssm-agent || true
systemctl restart amazon-ssm-agent || true
EOF

  tags = merge(local.tags, {
    Name = var.instance_name
  })
}
