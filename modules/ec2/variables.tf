variable "create_ec2" {
  description = "Whether to create the target EC2 instance and its SG"
  type        = bool
  default     = true
}

variable "dest_vpc_id" {
  description = "VPC ID to create resources in"
  type        = string
}

variable "dest_subnet_id" {
  description = "Subnet ID to launch the EC2 instance in"
  type        = string
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "instance_name" {
  type        = string
  description = "Name tag for the instance"
  default     = "ssm-managed-ec2"
}

variable "instance_profile_name" {
  description = "IAM Instance Profile name (must include AmazonSSMManagedInstanceCore)"
  type        = string
  default     = "EC2-Default-SSM-AD-Role"
}

variable "security_group_name" {
  type        = string
  description = "Name of the security group"
  default     = "ssm-managed-sg"
}

variable "ingress_rules" {
  description = "Ingress rules (CIDRs are LIST). Default is empty (no ingress)."
  type = list(object({
    description = optional(string)
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "egress_rules" {
  description = "Egress rules (CIDRs are LIST). Default is HTTPS only (Checkov-friendly)."
  type = list(object({
    description = optional(string)
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [
    {
      description = "Outbound HTTPS only"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    cost-centre : "1709144"
    account-code : "521835"
    portfolio-id : "cto"
    project-id : "cc"
    service-id : "core-platform"
    environment-type : "test"
    owner-business : "cc-andromeda"
    budget-holder : "corecloud@homeoffice.gov.uk"
    Costing : "test"
  }
}