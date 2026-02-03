data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
data "aws_iam_instance_profile" "ssm_profile" {
  name = var.instance_profile_name
}
# --- Security Group (CIDR ranges are LISTS) ---
resource "aws_security_group" "this" {
  name        = var.security_group_name
  description = "SG for SSM-managed EC2 instance"
  vpc_id      = var.dest_vpc_id
}

resource "aws_security_group" "this" {
  name        = var.security_group_name
  description = "SG for SSM-managed EC2 instance (no ingress by default)"
  vpc_id      = var.dest_vpc_id

  tags = merge(local.tags, {
    Name = var.security_group_name
  })
}

# Ingress rules: NONE by default (var.ingress_rules default = [])
resource "aws_security_group_rule" "ingress" {
  for_each = {
    for idx, r in var.ingress_rules : tostring(idx) => r
  }

  type              = "ingress"
  security_group_id = aws_security_group.this.id

  description = try(each.value.description, null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

# Egress rules: configurable (default allows all outbound)
resource "aws_security_group_rule" "egress" {
  for_each = {
    for idx, r in var.egress_rules : tostring(idx) => r
  }

  type              = "egress"
  security_group_id = aws_security_group.this.id

  description = try(each.value.description, null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.dest_subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]

  iam_instance_profile = data.aws_iam_instance_profile.this.name

  metadata_options {
    http_tokens = "required"
  }

  # Ensure SSM agent is running
  user_data = <<-EOF
    #!/bin/bash
    set -e
    systemctl enable amazon-ssm-agent || true
    systemctl restart amazon-ssm-agent || true
  EOF

  tags = merge(local.tags, {
    Name = var.instance_name
  })
}
