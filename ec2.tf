module "ec2" {
  source = "../modules/ec2"

  create_ec2            = var.create_ec2
  dest_vpc_id           = var.dest_vpc_id
  dest_subnet_id        = var.dest_subnet_id
  instance_type         = var.instance_type
  instance_name         = var.instance_name
  instance_profile_name = var.instance_profile_name
  security_group_name   = var.security_group_name

  ingress_rules = var.ingress_rules
  egress_rules  = var.egress_rules
  tags          = local.tags
}