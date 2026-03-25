################################################################################
# OIDC dynamic credentials (TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN)
# Applied to bootstrap and agency-managed deployer workspaces.
################################################################################

resource "tfe_variable" "workspace_oidc_env" {
  for_each = local.all_oidc_env_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "WRITTEN BY AUTOMATION: HCP Terraform OIDC dynamic credential config."
}

resource "tfe_variable" "account_portal_contract" {
  for_each = local.account_portal_contract_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  description  = "WRITTEN BY AUTOMATION: Account portal control-plane contract."
}

resource "tfe_variable" "bootstrap_control" {
  for_each = local.bootstrap_control_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  description  = "WRITTEN BY AUTOMATION: Bootstrap workspace control flag."
}

resource "tfe_variable" "service_workspace_inputs" {
  for_each = local.service_workspace_input_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  hcl          = true
  description  = "WRITTEN BY AUTOMATION: Service workspace bootstrap input."
}
