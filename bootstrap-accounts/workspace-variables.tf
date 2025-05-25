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