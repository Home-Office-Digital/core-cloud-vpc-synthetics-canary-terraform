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
  }
}

locals {
  slack_forwarder_name = "${var.environment}-slack-forwarder"
}