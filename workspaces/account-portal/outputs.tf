output "project_workspaces" {
  description = "Child project workspaces created by this account portal, keyed by blueprint."
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
  description = "Sorted list of enabled project blueprints."
  value       = sort(keys(local.enabled_projects))
}
