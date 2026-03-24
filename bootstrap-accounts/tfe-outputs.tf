data "tfe_outputs" "bootstrap_variable_sets" {
  organization = var.organization
  workspace    = var.bootstrap_varsets_workspace_name
}
