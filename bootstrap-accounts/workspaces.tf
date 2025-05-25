resource "tfe_workspace" "bootstrap_account" {
  for_each = var.accounts
  name = "bootstrap-${lower(each.value.product_name)}-${each.value.env}-${each.key}"
  description = "Terraform deployment to bootstrap the ${each.value.product_name} ${each.value.env}, ${each.key} account."
  allow_destroy_plan = true
  auto_apply = true
  speculative_enabled = false
  global_remote_state = false
  queue_all_runs = false
  organization = "core-aws"
  project_id   = var.project_id
  working_directory = "terraform"
  trigger_patterns = ["run-all-bootstrap-workspaces"]
  execution_mode = "remote"
  terraform_version = var.terraform_version
  tag_names = ["bootstrap", each.value.env, each.value.product_name]

  vcs_repo {
    identifier     = "bootstrap"
    branch         = "main"
    oauth_token_id = var.aws_core_oauth_token_id
  }
}