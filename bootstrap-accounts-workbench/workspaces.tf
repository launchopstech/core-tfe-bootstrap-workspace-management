module "workspaces" {
  source = "./../bootstrap-accounts"

  accounts                          = local.accounts
  project_id                        = data.tfe_project.bootstrap_workbench.id
  aws_core_oauth_token_id          = var.aws_core_oauth_token_id
  enable_aws_core_failure_notification = var.enable_aws_core_failure_notification
  environment                       = "workbench"
  terraform_version                = var.terraform_version
  tfe_prod_admin_token             = var.tfe_prod_admin_token
  vault_approle_role_id            = var.vault_approle_role_id
  vault_approle_secret_id          = var.vault_approle_secret_id
}