# Amazon Linux 2023
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "https_sg" {
  name        = "https-from-cidr"
  description = "Allow HTTPS from provided CIDR"
  vpc_id      = var.dest_vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_https_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "https-from-cidr" }
}

resource "aws_instance" "ec2" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type
  subnet_id     = var.dest_subnet_id

  vpc_security_group_ids = [aws_security_group.https_sg.id]


  tags = { Name = "ec2-https" }
}