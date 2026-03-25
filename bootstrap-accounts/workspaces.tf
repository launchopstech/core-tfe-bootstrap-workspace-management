################################################################################
# Bootstrap workspaces (agency-internal, one per account)
################################################################################

resource "tfe_workspace" "bootstrap_account" {
  for_each = local.normalized_accounts

  name                = "bootstrap-${each.value.client_id}-${each.value.env}-${each.value.account_id}"
  description         = each.value.description
  allow_destroy_plan  = true
  auto_apply          = true
  speculative_enabled = false
  global_remote_state = false
  queue_all_runs      = false
  organization        = var.organization
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
      condition     = can(regex("^[0-9]{12}$", each.value.account_id))
      error_message = "Account '${each.key}': account_id '${each.value.account_id}' must be a 12-digit AWS account ID."
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

resource "tfe_notification_configuration" "bootstrap_failure" {
  for_each         = { for k, v in tfe_workspace.bootstrap_account : k => v if var.enable_aws_core_failure_notification }
  name             = "bootstrap_failure_notification"
  enabled          = true
  destination_type = "email"
  triggers         = ["run:errored"]
  email_addresses  = var.notification_emails
  workspace_id     = each.value.id
}

################################################################################
# Account portal workspaces (client-facing, one per account)
# Resource name remains "team" to avoid needless state-address churn.
################################################################################

resource "tfe_workspace" "team" {
  for_each = local.normalized_accounts

  name                          = each.value.account_id
  description                   = "Account portal for ${each.value.client_id} ${each.value.env} (${each.value.account_id}). Client admins manage project requests here."
  allow_destroy_plan            = false
  auto_apply                    = false
  speculative_enabled           = true
  global_remote_state           = false
  queue_all_runs                = false
  organization                  = var.organization
  project_id                    = var.team_project_id
  working_directory             = each.value.portal_working_directory
  execution_mode                = "remote"
  terraform_version             = var.terraform_version
  structured_run_output_enabled = true

  tag_names = distinct(compact(concat(
    [
      "workspace-class-account-portal",
      "account-${each.value.account_id}",
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
      condition     = length(local.account_seed_missing_dependencies[each.key]) == 0
      error_message = "Account '${each.key}' seeds project_requests_json with services missing required dependencies: ${join(", ", sort(tolist(local.account_seed_missing_dependencies[each.key])))}."
    }

    precondition {
      condition     = length(local.account_seed_missing_required_variables[each.key]) == 0
      error_message = "Account '${each.key}' seeds project_requests_json with services missing required service_workspace_variables: ${join(", ", sort(tolist(local.account_seed_missing_required_variables[each.key])))}."
    }
  }
}

resource "tfe_notification_configuration" "team_failure" {
  for_each         = { for k, v in tfe_workspace.team : k => v if var.enable_aws_core_failure_notification }
  name             = "account_portal_failure_notification"
  enabled          = true
  destination_type = "email"
  triggers         = ["run:errored"]
  email_addresses  = var.notification_emails
  workspace_id     = each.value.id
}

################################################################################
# Agency-managed project workspaces (secure-baseline in MVP).
# Client-requestable blueprints are created by the account portal root.
################################################################################

resource "tfe_workspace" "service" {
  for_each = local.service_accounts

  name                          = each.key
  description                   = "Agency-managed project workspace for ${each.value.account.client_id} ${each.value.account.env} — ${each.value.service}."
  allow_destroy_plan            = false
  auto_apply                    = false
  speculative_enabled           = true
  global_remote_state           = false
  queue_all_runs                = false
  organization                  = var.organization
  project_id                    = var.project_id
  working_directory             = lookup(local.service_working_dirs, each.value.service, "workspaces/${each.value.service}")
  execution_mode                = "remote"
  terraform_version             = var.terraform_version
  structured_run_output_enabled = true

  tag_names = distinct(compact([
    "workspace-class-agency-project",
    "service-${each.value.service}",
    "account-${each.value.account.account_id}",
    "client-${each.value.account.client_id}",
    "env-${each.value.account.env}",
    "tier-${each.value.account.security_tier}",
    "family-${each.value.account.service_family}",
  ]))

  vcs_repo {
    identifier     = each.value.account.project_vcs_repo_identifier
    branch         = "main"
    oauth_token_id = var.aws_core_oauth_token_id
  }

  lifecycle {
    precondition {
      condition     = contains(keys(local.service_working_dirs), each.value.service)
      error_message = "Service '${each.value.service}' for '${each.key}' is not a known service. Allowed: ${join(", ", keys(local.service_working_dirs))}."
    }

    precondition {
      condition     = length(local.service_missing_dependencies[each.key]) == 0
      error_message = "Service '${each.value.service}' for '${each.key}' is missing required dependent services: ${join(", ", sort(tolist(local.service_missing_dependencies[each.key])))}."
    }

    precondition {
      condition     = length(local.service_missing_required_variables[each.key]) == 0
      error_message = "Service '${each.value.service}' for '${each.key}' is missing required service_workspace_variables: ${join(", ", sort(tolist(local.service_missing_required_variables[each.key])))}."
    }
  }
}

resource "tfe_notification_configuration" "service_failure" {
  for_each         = { for k, v in tfe_workspace.service : k => v if var.enable_aws_core_failure_notification }
  name             = "service_failure_notification"
  enabled          = true
  destination_type = "email"
  triggers         = ["run:errored"]
  email_addresses  = var.notification_emails
  workspace_id     = each.value.id
}

################################################################################
# Unified variable-set attachments and metadata variables
################################################################################

resource "tfe_workspace_variable_set" "all" {
  for_each = local.all_workspace_variable_sets

  workspace_id    = each.value.workspace_id
  variable_set_id = each.value.variable_set_id
}

resource "tfe_variable" "workspace_metadata" {
  for_each = local.all_metadata_variables

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  description  = "WRITTEN BY AUTOMATION: Workspace metadata."
}
