data "tfe_outputs" "secure_baseline" {
  organization = var.hcp_terraform_organization
  workspace    = var.secure_baseline_workspace_name
}

data "tfe_outputs" "vpc" {
  count = local.enable_vpc ? 1 : 0

  organization = var.hcp_terraform_organization
  workspace    = var.vpc_workspace_name
}
