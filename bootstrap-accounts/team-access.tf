data "tfe_team" "client_admin" {
  for_each = local.client_admin_team_names

  name         = each.value
  organization = var.organization
}

resource "tfe_team_access" "account_portal_client_admin" {
  for_each = {
    for k, account in local.normalized_accounts : k => account
    if account.client_admin_team_name != ""
  }

  team_id      = data.tfe_team.client_admin[each.value.client_admin_team_name].id
  workspace_id = tfe_workspace.team[each.key].id
  access       = "write"
}
