# resource "tfe_variable" "environment" {
#   for_each    = local.accounts
#   key         = "environment"
#   value       = each.value.env
#   category    = "terraform"
#   workspace_id = tfe_workspace.bootstrap_account[each.key].id
#   description = "WRITTEN BY AUTOMATION: The environment for the AWS Account."
# }

# resource "tfe_variable" "aws_account_id" {
#   for_each    = local.accounts
#   key         = "aws_account_id"
#   value       = each.key
#   category    = "terraform"
#   workspace_id = tfe_workspace.bootstrap_account[each.key].id
#   description = "WRITTEN BY AUTOMATION: The ID of the AWS Account."
# }

################################################################################
# OIDC dynamic credentials — bootstrap workspaces
################################################################################

resource "tfe_variable" "bootstrap_oidc_env" {
  for_each = local.bootstrap_oidc_env_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "WRITTEN BY AUTOMATION: HCP Terraform OIDC dynamic credential config."
}

################################################################################
# OIDC dynamic credentials — team workspaces
################################################################################

resource "tfe_variable" "team_oidc_env" {
  for_each = local.team_oidc_env_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "WRITTEN BY AUTOMATION: HCP Terraform OIDC dynamic credential config."
}
