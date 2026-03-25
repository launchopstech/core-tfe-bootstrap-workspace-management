data "tfe_outputs" "bootstrap_control_plane" {
  organization = var.organization
  workspace    = var.bootstrap_varsets_workspace_name
}
