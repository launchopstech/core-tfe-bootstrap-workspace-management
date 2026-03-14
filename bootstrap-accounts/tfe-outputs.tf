data "tfe_outputs" "bootstrap_variable_sets" {
  organization = "core-aws"
  workspace    = var.bootstrap_varsets_workspace_name
}
