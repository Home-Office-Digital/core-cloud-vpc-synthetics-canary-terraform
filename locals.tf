locals {
  tags = {
    cost-centre : "1709144"
    account-code : "521835"
    portfolio-id : "cto"
    project-id : "cc"
    service-id : "core-platform"
    source-repo : "core-cloud-vpc-synthetics-canary-terraform"
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