output "control_plane_workspace_ids" {
  value = {
    for workspace_name, workspace in tfe_workspace.control_plane : workspace_name => workspace.id
  }
}
