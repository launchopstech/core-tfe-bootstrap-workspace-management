################################################################################
# OIDC dynamic credentials (TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN)
# Applied to bootstrap, team, and service workspaces.
################################################################################

resource "tfe_variable" "workspace_oidc_env" {
  for_each = local.all_oidc_env_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "WRITTEN BY AUTOMATION: HCP Terraform OIDC dynamic credential config."
}
