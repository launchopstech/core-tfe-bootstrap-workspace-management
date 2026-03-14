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
