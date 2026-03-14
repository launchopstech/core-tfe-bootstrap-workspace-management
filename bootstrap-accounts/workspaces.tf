resource "tfe_workspace" "bootstrap_account" {
  for_each = local.normalized_accounts

  name                = "bootstrap-${each.value.client_id}-${each.value.env}-${each.key}"
  description         = each.value.description
  allow_destroy_plan  = true
  auto_apply          = true
  speculative_enabled = false
  global_remote_state = false
  queue_all_runs      = false
  organization        = "core-aws"
  project_id          = var.project_id
  working_directory   = each.value.working_directory
  trigger_patterns    = ["run-all-bootstrap-workspaces"]
  execution_mode      = "remote"
  terraform_version   = var.terraform_version
  tag_names = distinct(compact(concat(
    [
      "bootstrap",
      "workspace-class-bootstrap-account",
      "client-${each.value.client_id}",
      "env-${each.value.env}",
      "tier-${each.value.security_tier}",
      "family-${each.value.service_family}",
    ],
    each.value.workspace_tags,
  )))

  vcs_repo {
    identifier     = each.value.vcs_repo_identifier
    branch         = "main"
    oauth_token_id = var.aws_core_oauth_token_id
  }
}

resource "tfe_workspace_variable_set" "bootstrap_account" {
  for_each = local.workspace_variable_sets

  workspace_id    = each.value.workspace_id
  variable_set_id = each.value.variable_set_id
}

resource "tfe_variable" "bootstrap_account_metadata" {
  for_each = local.workspace_metadata_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  description  = "WRITTEN BY AUTOMATION: Bootstrap workspace metadata."
}
