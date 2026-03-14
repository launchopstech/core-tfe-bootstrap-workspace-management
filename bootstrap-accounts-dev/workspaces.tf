module "workspaces" {
  source = "./../bootstrap-accounts"

  accounts                             = local.accounts
  project_id                           = data.tfe_outputs.bootstrap_control_plane.values["bootstrap_dev_project_id"]
  aws_core_oauth_token_id              = var.aws_core_oauth_token_id
  enable_aws_core_failure_notification = var.enable_aws_core_failure_notification
  terraform_version                    = var.terraform_version
  bootstrap_varsets_workspace_name     = var.bootstrap_varsets_workspace_name
}
