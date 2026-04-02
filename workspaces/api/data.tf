data "tfe_outputs" "secure_baseline" {
  organization = var.hcp_terraform_organization
  workspace    = var.secure_baseline_workspace_name
}

data "tfe_outputs" "vpc" {
  count        = local.needs_vpc ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = var.vpc_workspace_name
}

data "tfe_outputs" "rds" {
  count        = local.needs_rds ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = var.rds_workspace_name
}

data "tfe_outputs" "dns" {
  count        = local.use_dns_workspace ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = var.dns_workspace_name
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
