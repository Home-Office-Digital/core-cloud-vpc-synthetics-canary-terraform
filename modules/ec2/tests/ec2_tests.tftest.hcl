variables {
  dest_vpc_id           = "vpc-12345678"
  dest_subnet_id        = "subnet-12345678"
  instance_type         = "t3.micro"
  instance_name         = "ec2-test"
  security_group_name   = "ec2-test-sg"
  instance_profile_name = "EC2-Default-SSM-AD-Role"
}

mock_provider "aws" {}

run "ec2_defaults_plan" {
  command = plan

  assert {
    condition     = length(aws_instance.this) == 1
    error_message = "Expected one EC2 instance when create_ec2 is true."
  }

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "Expected one security group when create_ec2 is true."
  }

  assert {
    condition     = aws_instance.this[0].instance_type == "t3.micro"
    error_message = "Unexpected instance type."
  }

  assert {
    condition     = aws_instance.this[0].associate_public_ip_address == false
    error_message = "Instance must not associate a public IP."
  }

  assert {
    condition     = aws_instance.this[0].monitoring == true
    error_message = "Detailed monitoring must be enabled."
  }

  assert {
    condition     = aws_instance.this[0].metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }

  assert {
    condition     = aws_instance.this[0].metadata_options[0].http_endpoint == "enabled"
    error_message = "Instance metadata endpoint must stay enabled."
  }

  assert {
    condition     = aws_instance.this[0].ebs_optimized == true
    error_message = "EBS optimization must be enabled."
  }

  assert {
    condition     = aws_instance.this[0].iam_instance_profile == "EC2-Default-SSM-AD-Role"
    error_message = "Unexpected IAM instance profile attached to EC2."
  }

  assert {
    condition     = aws_instance.this[0].root_block_device[0].encrypted == true
    error_message = "Root volume must be encrypted."
  }

  assert {
    condition     = aws_instance.this[0].root_block_device[0].volume_type == "gp3"
    error_message = "Root volume must use gp3."
  }

  assert {
    condition     = aws_instance.this[0].tags["Name"] == "ec2-test"
    error_message = "Instance Name tag must match instance_name."
  }

  assert {
    condition     = aws_security_group.this[0].tags["Name"] == "ec2-test-sg"
    error_message = "Security group Name tag must match security_group_name."
  }

  assert {
    condition     = length(aws_security_group_rule.ingress) == 0
    error_message = "No ingress rules are expected by default."
  }

  assert {
    condition     = length(aws_security_group_rule.egress) == 1
    error_message = "Expected one default egress rule."
  }

  assert {
    condition     = aws_security_group_rule.egress["0"].from_port == 443 && aws_security_group_rule.egress["0"].to_port == 443 && aws_security_group_rule.egress["0"].protocol == "tcp"
    error_message = "Default egress rule must allow HTTPS only."
  }

  assert {
    condition     = aws_security_group_rule.egress["0"].cidr_blocks == ["0.0.0.0/0"]
    error_message = "Default egress CIDR must be 0.0.0.0/0."
  }
}

run "ec2_custom_rules_plan" {
  command = plan

  variables {
    ingress_rules = [
      {
        description = "Allow HTTPS from corp network"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/8"]
      }
    ]

    egress_rules = [
      {
        description = "Allow HTTPS"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
      },
      {
        description = "Allow DNS"
        from_port   = 53
        to_port     = 53
        protocol    = "udp"
        cidr_blocks = ["10.0.0.2/32"]
      }
    ]
  }

  assert {
    condition     = length(aws_security_group_rule.ingress) == 1
    error_message = "Expected one custom ingress rule."
  }

  assert {
    condition     = aws_security_group_rule.ingress["0"].from_port == 443 && aws_security_group_rule.ingress["0"].to_port == 443 && aws_security_group_rule.ingress["0"].protocol == "tcp"
    error_message = "Custom ingress rule was not rendered correctly."
  }

  assert {
    condition     = aws_security_group_rule.ingress["0"].cidr_blocks == ["10.0.0.0/8"]
    error_message = "Custom ingress CIDR was not rendered correctly."
  }

  assert {
    condition     = length(aws_security_group_rule.egress) == 2
    error_message = "Expected two custom egress rules."
  }

  assert {
    condition     = aws_security_group_rule.egress["1"].from_port == 53 && aws_security_group_rule.egress["1"].to_port == 53 && aws_security_group_rule.egress["1"].protocol == "udp"
    error_message = "Custom DNS egress rule was not rendered correctly."
  }
}

run "ec2_disabled_plan" {
  command = plan

  variables {
    create_ec2 = false
  }

  assert {
    condition     = length(aws_instance.this) == 0
    error_message = "No EC2 instance should be created when create_ec2 is false."
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "No security group should be created when create_ec2 is false."
  }

  assert {
    condition     = length(aws_security_group_rule.ingress) == 0
    error_message = "No ingress rules should exist when create_ec2 is false."
  }

  assert {
    condition     = length(aws_security_group_rule.egress) == 0
    error_message = "No egress rules should exist when create_ec2 is false."
  }

  assert {
    condition     = output.instance_id == null
    error_message = "instance_id output should be null when create_ec2 is false."
  }

  assert {
    condition     = output.security_group_id == null
    error_message = "security_group_id output should be null when create_ec2 is false."
  }
}
