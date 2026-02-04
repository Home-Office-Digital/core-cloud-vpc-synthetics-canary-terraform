locals {
  tags = {
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

locals {
  slack_forwarder_name = "${var.environment}-slack-forwarder"
}

locals {
  signer_name_prefix = substr(
    replace("${var.environment}slackfw", "-", ""),
    0,
    38
  )
}

locals {
  dest_ip = var.create_ec2 ? aws_instance.this[0].private_dns : ""
}