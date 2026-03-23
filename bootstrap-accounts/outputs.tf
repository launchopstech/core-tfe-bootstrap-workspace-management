output "bootstrap_account_workspaces" {
  value = {
    for account_id, workspace in tfe_workspace.bootstrap_account : account_id => {
      id                = workspace.id
      name              = workspace.name
      working_directory = workspace.working_directory
      tag_names         = workspace.tag_names
      project_id        = workspace.project_id
      metadata          = local.normalized_accounts[account_id].metadata
    }
  }
}

output "team_workspaces" {
  description = "Client-facing team workspaces keyed by AWS account ID."
  value = {
    for account_id, workspace in tfe_workspace.team : account_id => {
      id         = workspace.id
      name       = workspace.name
      project_id = workspace.project_id
      tag_names  = workspace.tag_names
    }
  }
}
