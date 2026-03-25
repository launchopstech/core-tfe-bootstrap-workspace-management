terraform {
  required_version = ">= 1.2"
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.49.0"
    }
  }
}

locals {
  client_admin_team_name = trimspace(var.client_admin_team_name)
  notification_emails    = try(tolist(jsondecode(var.notification_emails_json)), [])
  account_name           = coalesce(var.aws_account_name, var.aws_account_id)
  normalized_tier        = coalesce(var.security_tier, "")
  normalized_family      = coalesce(var.service_family, "platform")

  project_catalog = {
    vpc = {
      working_directory    = "workspaces/vpc"
      default_dependencies = toset([])
      required_inputs      = toset(["cidr_block", "azs", "private_subnets", "public_subnets"])
    }
    rds = {
      working_directory    = "workspaces/rds"
      default_dependencies = toset(["vpc"])
      required_inputs      = toset([])
    }
  }

  project_requests_document = can(jsondecode(var.project_requests_json)) ? jsondecode(var.project_requests_json) : {}
  requested_projects_raw    = try(local.project_requests_document.projects, {})

  requested_projects = {
    for project_key, project in local.requested_projects_raw : project_key => {
      enabled = try(project.enabled, false)
      inputs = try({
        for input_key, input_value in project.inputs :
        input_key => input_value
      }, {})
      requested_dependencies = try(toset(project.depends_on), toset([]))
    }
  }

  invalid_project_keys = setsubtract(
    toset(keys(local.requested_projects)),
    toset(keys(local.project_catalog)),
  )

  enabled_projects = {
    for project_key, project in local.requested_projects : project_key => merge(project, {
      dependencies = setunion(
        local.project_catalog[project_key].default_dependencies,
        project.requested_dependencies,
      )
    })
    if project.enabled && contains(keys(local.project_catalog), project_key)
  }

  project_missing_dependencies = {
    for project_key, project in local.enabled_projects :
    project_key => setsubtract(
      project.dependencies,
      toset(keys(local.enabled_projects)),
    )
  }

  project_missing_required_inputs = {
    for project_key, project in local.enabled_projects :
    project_key => setsubtract(
      setunion(
        local.project_catalog[project_key].required_inputs,
        project_key == "vpc" && contains(keys(local.enabled_projects), "rds") ? toset(["database_subnets"]) : toset([]),
      ),
      toset(keys(project.inputs)),
    )
  }

  selected_services_json = jsonencode(sort(keys(local.enabled_projects)))

  workspace_variable_sets = {
    for attachment in flatten([
      for project_key, workspace in tfe_workspace.project : concat(
        var.bootstrap_global_variable_set_id == null ? [] : [{
          map_key         = "${project_key}:global"
          workspace_id    = workspace.id
          variable_set_id = var.bootstrap_global_variable_set_id
        }],
        var.environment_variable_set_id == null ? [] : [{
          map_key         = "${project_key}:environment"
          workspace_id    = workspace.id
          variable_set_id = var.environment_variable_set_id
        }],
        var.security_tier_variable_set_id == null ? [] : [{
          map_key         = "${project_key}:security-tier"
          workspace_id    = workspace.id
          variable_set_id = var.security_tier_variable_set_id
        }],
      )
      ]) : attachment.map_key => {
      workspace_id    = attachment.workspace_id
      variable_set_id = attachment.variable_set_id
    }
  }

  workspace_metadata = {
    for item in flatten([
      for project_key, workspace in tfe_workspace.project : [
        {
          map_key      = "${project_key}:client_id"
          workspace_id = workspace.id
          key          = "client_id"
          value        = var.client_id
        },
        {
          map_key      = "${project_key}:aws_account_id"
          workspace_id = workspace.id
          key          = "aws_account_id"
          value        = var.aws_account_id
        },
        {
          map_key      = "${project_key}:aws_account_name"
          workspace_id = workspace.id
          key          = "aws_account_name"
          value        = local.account_name
        },
        {
          map_key      = "${project_key}:environment"
          workspace_id = workspace.id
          key          = "environment"
          value        = var.environment
        },
        {
          map_key      = "${project_key}:aws_region"
          workspace_id = workspace.id
          key          = "aws_region"
          value        = var.aws_region
        },
        {
          map_key      = "${project_key}:security_tier"
          workspace_id = workspace.id
          key          = "security_tier"
          value        = local.normalized_tier
        },
        {
          map_key      = "${project_key}:service_family"
          workspace_id = workspace.id
          key          = "service_family"
          value        = local.normalized_family
        },
        {
          map_key      = "${project_key}:selected_services"
          workspace_id = workspace.id
          key          = "selected_services"
          value        = local.selected_services_json
        },
      ]
      ]) : item.map_key => {
      workspace_id = item.workspace_id
      key          = item.key
      value        = item.value
    }
  }

  workspace_oidc_env = {
    for item in flatten([
      for project_key, workspace in tfe_workspace.project : [
        {
          map_key      = "${project_key}:TFC_AWS_PROVIDER_AUTH"
          workspace_id = workspace.id
          key          = "TFC_AWS_PROVIDER_AUTH"
          value        = "true"
        },
        {
          map_key      = "${project_key}:TFC_AWS_RUN_ROLE_ARN"
          workspace_id = workspace.id
          key          = "TFC_AWS_RUN_ROLE_ARN"
          value        = var.terraform_run_role_arn
        },
      ]
      ]) : item.map_key => {
      workspace_id = item.workspace_id
      key          = item.key
      value        = item.value
    }
  }

  workspace_inputs = {
    for item in flatten([
      for project_key, workspace in tfe_workspace.project : concat(
        [
          {
            map_key      = "${project_key}:hcp_terraform_organization"
            workspace_id = workspace.id
            key          = "hcp_terraform_organization"
            value        = var.organization
          },
          {
            map_key      = "${project_key}:secure_baseline_workspace_name"
            workspace_id = workspace.id
            key          = "secure_baseline_workspace_name"
            value        = "${var.aws_account_id}-secure-baseline"
          },
        ],
        project_key == "rds" ? [{
          map_key      = "${project_key}:vpc_workspace_name"
          workspace_id = workspace.id
          key          = "vpc_workspace_name"
          value        = "${var.aws_account_id}-vpc"
        }] : [],
        [
          for input_key, input_value in local.enabled_projects[project_key].inputs : {
            map_key      = "${project_key}:${input_key}"
            workspace_id = workspace.id
            key          = input_key
            value        = input_value
          }
        ]
      )
      ]) : item.map_key => {
      workspace_id = item.workspace_id
      key          = item.key
      value        = item.value
    }
  }
}

resource "terraform_data" "project_request_validation" {
  input = local.requested_projects_raw

  lifecycle {
    precondition {
      condition     = can(jsondecode(var.project_requests_json))
      error_message = "project_requests_json must be valid JSON."
    }

    precondition {
      condition     = can(local.project_requests_document.projects)
      error_message = "project_requests_json must contain a top-level 'projects' object."
    }

    precondition {
      condition     = length(local.invalid_project_keys) == 0
      error_message = "project_requests_json contains unsupported blueprints: ${join(", ", sort(tolist(local.invalid_project_keys)))}. Supported blueprints: ${join(", ", sort(keys(local.project_catalog)))}."
    }
  }
}

data "tfe_team" "client_admin" {
  count = local.client_admin_team_name != "" ? 1 : 0

  name         = local.client_admin_team_name
  organization = var.organization
}

resource "tfe_workspace" "project" {
  for_each = local.enabled_projects

  name                          = "${var.aws_account_id}-${each.key}"
  description                   = "Project workspace for ${var.client_id} ${var.environment} ${each.key}."
  allow_destroy_plan            = false
  auto_apply                    = false
  speculative_enabled           = true
  global_remote_state           = false
  queue_all_runs                = false
  organization                  = var.organization
  project_id                    = var.project_id
  working_directory             = local.project_catalog[each.key].working_directory
  execution_mode                = "remote"
  terraform_version             = var.terraform_version
  structured_run_output_enabled = true

  tag_names = distinct(compact([
    "workspace-class-project",
    "account-${var.aws_account_id}",
    "blueprint-${each.key}",
    "client-${var.client_id}",
    "env-${var.environment}",
    local.normalized_tier != "" ? "tier-${local.normalized_tier}" : null,
    local.normalized_family != "" ? "family-${local.normalized_family}" : null,
  ]))

  vcs_repo {
    identifier     = var.project_vcs_repo_identifier
    branch         = "main"
    oauth_token_id = var.project_vcs_oauth_token_id
  }

  lifecycle {
    precondition {
      condition     = length(local.project_missing_dependencies[each.key]) == 0
      error_message = "Project '${each.key}' is missing required dependencies: ${join(", ", sort(tolist(local.project_missing_dependencies[each.key])))}."
    }

    precondition {
      condition     = length(local.project_missing_required_inputs[each.key]) == 0
      error_message = "Project '${each.key}' is missing required inputs: ${join(", ", sort(tolist(local.project_missing_required_inputs[each.key])))}."
    }
  }

  depends_on = [terraform_data.project_request_validation]
}

resource "tfe_team_access" "project_client_admin" {
  for_each = local.client_admin_team_name == "" ? {} : tfe_workspace.project

  team_id      = data.tfe_team.client_admin[0].id
  workspace_id = each.value.id
  access       = "write"
}

resource "tfe_notification_configuration" "project_failure" {
  for_each = length(local.notification_emails) == 0 ? {} : tfe_workspace.project

  name             = "project_failure_notification"
  enabled          = true
  destination_type = "email"
  triggers         = ["run:errored"]
  email_addresses  = local.notification_emails
  workspace_id     = each.value.id
}

resource "tfe_workspace_variable_set" "project" {
  for_each = local.workspace_variable_sets

  workspace_id    = each.value.workspace_id
  variable_set_id = each.value.variable_set_id
}

resource "tfe_variable" "project_metadata" {
  for_each = local.workspace_metadata

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  description  = "WRITTEN BY AUTOMATION: Project workspace metadata."
}

resource "tfe_variable" "project_oidc_env" {
  for_each = local.workspace_oidc_env

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "WRITTEN BY AUTOMATION: HCP Terraform OIDC dynamic credential config."
}

resource "tfe_variable" "project_inputs" {
  for_each = local.workspace_inputs

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = jsonencode(each.value.value)
  category     = "terraform"
  hcl          = true
  description  = "WRITTEN BY AUTOMATION: Account portal project input."
}
