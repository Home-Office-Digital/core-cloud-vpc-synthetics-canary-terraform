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
    regexreplace("${var.environment}slackfw", "[^A-Za-z0-9]", ""),
    0,
    38
  )
}