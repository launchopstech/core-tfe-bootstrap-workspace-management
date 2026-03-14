data "tfe_outputs" "bootstrap_control_plane" {
  organization = "core-aws"
  workspace    = var.bootstrap_varsets_workspace_name
}
