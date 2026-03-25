output "project_workspaces" {
  description = "Child deployer workspaces created by this account portal, keyed by blueprint."
  value = {
    for project_key, workspace in tfe_workspace.project : project_key => {
      id                = workspace.id
      name              = workspace.name
      working_directory = workspace.working_directory
      project_id        = workspace.project_id
      tag_names         = workspace.tag_names
    }
  }
}

output "enabled_blueprints" {
  description = "Sorted list of blueprint deployers currently requested through the account portal."
  value       = sort(keys(local.enabled_projects))
}
