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

  lifecycle {
    precondition {
      condition     = can(regex("^[0-9]{12}$", each.key))
      error_message = "Account key '${each.key}' must be a 12-digit AWS account ID."
    }

    precondition {
      condition     = contains(["dev", "qa", "prod", "workbench", "sbx"], each.value.env)
      error_message = "Account '${each.key}': env '${each.value.env}' is not allowed. Must be one of: dev, qa, prod, workbench, sbx."
    }

    precondition {
      condition     = contains(["standard", "high"], each.value.security_tier)
      error_message = "Account '${each.key}': security_tier '${each.value.security_tier}' is not allowed. Must be one of: standard, high."
    }

    precondition {
      condition     = each.value.client_id != ""
      error_message = "Account '${each.key}': client_id (or product_name) must be set and non-empty."
    }

    precondition {
      condition     = each.value.vcs_repo_identifier != "bootstrap"
      error_message = "Account '${each.key}': vcs_repo_identifier must be set to a real repo (org/repo). Got default placeholder 'bootstrap'."
    }
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

################################################################################
# Team workspaces (client-facing, named by AWS account ID)
################################################################################

resource "tfe_workspace" "team" {
  for_each = local.normalized_accounts

  name                          = each.key
  description                   = "Team workspace for ${each.value.client_id} ${each.value.env}. Add project workspaces here."
  allow_destroy_plan            = false
  auto_apply                    = false
  speculative_enabled           = true
  global_remote_state           = false
  queue_all_runs                = false
  organization                  = "core-aws"
  project_id                    = var.team_project_id
  execution_mode                = "remote"
  terraform_version             = var.terraform_version
  structured_run_output_enabled = true

  tag_names = distinct(compact([
    "workspace-class-team",
    "client-${each.value.client_id}",
    "env-${each.value.env}",
    "tier-${each.value.security_tier}",
    "family-${each.value.service_family}",
  ]))
}

resource "tfe_workspace_variable_set" "team" {
  for_each = local.team_workspace_variable_sets

  workspace_id    = each.value.workspace_id
  variable_set_id = each.value.variable_set_id
}

resource "tfe_variable" "team_metadata" {
  for_each = local.team_metadata_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  description  = "WRITTEN BY AUTOMATION: Team workspace metadata."
}

resource "tfe_notification_configuration" "team_failure" {
  for_each         = var.enable_aws_core_failure_notification ? tfe_workspace.team : {}
  name             = "team_failure_notification"
  enabled          = true
  destination_type = "email"
  triggers         = ["run:errored"]
  email_addresses  = ["bomatra@gmail.com"]
  workspace_id     = each.value.id
}
