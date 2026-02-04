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

  signer_name_prefix = substr(
    replace("${var.environment}slackfw", "-", ""),
    0,
    38
  )

  # Prefer module-created EC2 DNS; fallback to input
  target_ips_effective = coalesce(module.target_ec2.ec2_private_dns_name, var.target_ips, "")

  # Canary expects a single DEST_IP; take first if comma-separated, safely
  dest_ip = length(trimspace(local.target_ips_effective)) > 0 ? trimspace(split(",", local.target_ips_effective)[0]) : ""
}