output "bootstrap_account_workspaces" {
  description = "Bootstrap workspaces keyed by the account entry key."
  value = {
    for k, workspace in tfe_workspace.bootstrap_account : k => {
      id                = workspace.id
      name              = workspace.name
      working_directory = workspace.working_directory
      tag_names         = workspace.tag_names
      project_id        = workspace.project_id
      account_id        = local.normalized_accounts[k].account_id
      metadata          = local.normalized_accounts[k].metadata
    }
  }
}

output "account_portal_workspaces" {
  description = "Client-facing account portal workspaces keyed by the account entry key."
  value = {
    for k, workspace in tfe_workspace.team : k => {
      id         = workspace.id
      name       = workspace.name
      project_id = workspace.project_id
      tag_names  = workspace.tag_names
      account_id = local.normalized_accounts[k].account_id
    }
  }
}

output "team_workspaces" {
  description = "Deprecated alias for account_portal_workspaces."
  value = {
    for k, workspace in tfe_workspace.team : k => {
      id         = workspace.id
      name       = workspace.name
      project_id = workspace.project_id
      tag_names  = workspace.tag_names
      account_id = local.normalized_accounts[k].account_id
    }
  }
}

output "agency_project_workspaces" {
  description = "Agency-managed project workspaces keyed by {workspace_prefix}-{service}."
  value = {
    for k, workspace in tfe_workspace.service : k => {
      id                = workspace.id
      name              = workspace.name
      working_directory = workspace.working_directory
      project_id        = workspace.project_id
      tag_names         = workspace.tag_names
      account_id        = local.service_accounts[k].account.account_id
      service           = local.service_accounts[k].service
    }
  }
}

output "service_workspaces" {
  description = "Deprecated alias for agency_project_workspaces."
  value = {
    for k, workspace in tfe_workspace.service : k => {
      id                = workspace.id
      name              = workspace.name
      working_directory = workspace.working_directory
      project_id        = workspace.project_id
      tag_names         = workspace.tag_names
      account_id        = local.service_accounts[k].account.account_id
      service           = local.service_accounts[k].service
    }
  }
}
