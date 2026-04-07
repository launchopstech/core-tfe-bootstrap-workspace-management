terraform {
  required_version = ">= 1.2"
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.49.0"
    }
  }
}

# Portal/factory root. This workspace reads project_requests_json and creates
# child deployer workspaces such as <client>-<env>-vpc and <client>-<env>-rds.
# It does not deploy those AWS resources itself.

locals {
  client_admin_team_name = trimspace(var.client_admin_team_name)
  notification_emails    = try(tolist(jsondecode(var.notification_emails_json)), [])
  workspace_prefix       = "${var.client_id}-${var.environment}"
  account_name           = coalesce(var.aws_account_name, var.aws_account_id)
  normalized_tier        = coalesce(var.security_tier, "")
  normalized_family      = coalesce(var.service_family, "platform")

  project_catalog = {
    vpc = {
      working_directory    = "workspaces/vpc"
      default_dependencies = toset(["secure-baseline"])
      required_inputs      = toset(["cidr_block", "azs", "private_subnets", "public_subnets"])
    }
    rds = {
      working_directory    = "workspaces/rds"
      default_dependencies = toset(["vpc"])
      required_inputs      = toset([])
    }
    dns = {
      working_directory    = "workspaces/dns"
      default_dependencies = toset([])
      required_inputs      = toset(["dns_config_json"])
    }
    waf = {
      working_directory    = "workspaces/waf"
      default_dependencies = toset([])
      required_inputs      = toset(["waf_config_json"])
    }
    secrets = {
      working_directory    = "workspaces/secrets"
      default_dependencies = toset(["secure-baseline"])
      required_inputs      = toset(["secrets_config_json"])
    }
    lambda = {
      working_directory    = "workspaces/lambda"
      default_dependencies = toset(["secure-baseline"])
      required_inputs      = toset(["lambda_config_json"])
    }
    api = {
      working_directory    = "workspaces/api"
      default_dependencies = toset(["secure-baseline", "vpc", "rds"])
      required_inputs      = toset(["api_config_json"])
    }
  }

  project_requests_document            = can(jsondecode(var.project_requests_json)) ? jsondecode(var.project_requests_json) : {}
  requested_projects_raw               = try(local.project_requests_document.projects, {})
  service_workspace_ownership_document = can(jsondecode(var.service_workspace_ownership_json)) ? jsondecode(var.service_workspace_ownership_json) : {}
  resolved_service_workspace_ownership = merge(
    { for project_key in keys(local.project_catalog) : project_key => "client" },
    {
      secrets = "agency"
    },
    {
      for service_name, owner in local.service_workspace_ownership_document :
      service_name => lower(trimspace(owner))
      if contains(keys(local.project_catalog), service_name)
    },
  )
  agency_managed_project_keys = toset([
    for project_key, owner in local.resolved_service_workspace_ownership : project_key
    if owner == "agency"
  ])
  portal_managed_project_keys = toset([
    for project_key in keys(local.project_catalog) : project_key
    if !contains(local.agency_managed_project_keys, project_key)
  ])

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
  invalid_ownership_values = toset([
    for service_name, owner in local.service_workspace_ownership_document :
    "${service_name}=${owner}"
    if contains(keys(local.project_catalog), service_name) && !contains(["client", "agency"], lower(trimspace(owner)))
  ])
  invalid_requested_agency_managed_project_keys = toset([
    for project_key, project in local.requested_projects : project_key
    if project.enabled && contains(local.agency_managed_project_keys, project_key)
  ])

  # Infer vpc dependency for lambda when lambda_config_json.network.enabled = true
  _lambda_needs_vpc = try(local.requested_projects["lambda"].inputs["lambda_config_json"].network.enabled, false)
  # Infer secrets dependency for lambda when lambda_config_json.secret_refs is non-empty
  _lambda_needs_secrets = try(length(keys(local.requested_projects["lambda"].inputs["lambda_config_json"].secret_refs)) > 0, false)
  # Infer dns dependency for api when any custom domain omits hosted_zone_id
  _api_needs_dns = try(anytrue([
    for domain_key, domain in local.requested_projects["api"].inputs["api_config_json"].gateway.custom_domains :
    trimspace(try(domain.hosted_zone_id, "")) == ""
  ]), false)
  # Infer WAF dependency for api when gateway.waf.enabled = true
  _api_needs_waf = try(local.requested_projects["api"].inputs["api_config_json"].gateway.waf.enabled, false)
  # Infer secrets dependency for api when any lambda declares secret_refs
  _api_needs_secrets = try(anytrue([
    for lambda_key, lambda_cfg in local.requested_projects["api"].inputs["api_config_json"].lambdas :
    length(keys(try(lambda_cfg.secret_refs, {}))) > 0
  ]), false)

  enabled_projects = {
    for project_key, project in local.requested_projects : project_key => merge(project, {
      dependencies = setunion(
        local.project_catalog[project_key].default_dependencies,
        project.requested_dependencies,
        # Infer vpc dependency for lambda when network.enabled = true
        project_key == "lambda" && local._lambda_needs_vpc ? toset(["vpc"]) : toset([]),
        # Infer secrets dependency for lambda when secret_refs are configured
        project_key == "lambda" && local._lambda_needs_secrets ? toset(["secrets"]) : toset([]),
        # Infer dns dependency for api when custom domains rely on dns workspace outputs
        project_key == "api" && local._api_needs_dns ? toset(["dns"]) : toset([]),
        # Infer WAF dependency for api when gateway.waf.enabled = true
        project_key == "api" && local._api_needs_waf ? toset(["waf"]) : toset([]),
        # Infer secrets dependency for api when any lambda declares secret_refs
        project_key == "api" && local._api_needs_secrets ? toset(["secrets"]) : toset([]),
      )
    })
    if project.enabled && contains(keys(local.project_catalog), project_key)
  }

  # Only check dependencies that are portal-managed (in project_catalog).
  # External dependencies (e.g. secure-baseline) are agency-managed and assumed to exist.
  project_missing_dependencies = {
    for project_key, project in local.enabled_projects :
    project_key => setsubtract(
      setintersection(project.dependencies, local.portal_managed_project_keys),
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
        # Organization — all workspaces may need it for tfe_outputs reads
        [
          {
            map_key      = "${project_key}:hcp_terraform_organization"
            workspace_id = workspace.id
            key          = "hcp_terraform_organization"
            value        = var.organization
          },
        ],
        # Dependency workspace names — derived from the dependency graph
        # Variable key uses underscores (e.g. secure-baseline → secure_baseline_workspace_name)
        [
          for dep in local.enabled_projects[project_key].dependencies : {
            map_key      = "${project_key}:${replace(dep, "-", "_")}_workspace_name"
            workspace_id = workspace.id
            key          = "${replace(dep, "-", "_")}_workspace_name"
            value        = "${local.workspace_prefix}-${dep}"
          }
        ],
        # Service-specific inputs from project_requests_json
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
      condition     = can(jsondecode(var.service_workspace_ownership_json))
      error_message = "service_workspace_ownership_json must be valid JSON."
    }

    precondition {
      condition     = can(local.project_requests_document.projects)
      error_message = "project_requests_json must contain a top-level 'projects' object."
    }

    precondition {
      condition     = length(local.invalid_project_keys) == 0
      error_message = "project_requests_json contains unsupported blueprints: ${join(", ", sort(tolist(local.invalid_project_keys)))}. Supported blueprints: ${join(", ", sort(keys(local.project_catalog)))}."
    }

    precondition {
      condition     = length(local.invalid_ownership_values) == 0
      error_message = "service_workspace_ownership_json contains invalid values. Supported values are client or agency. Invalid entries: ${join(", ", sort(tolist(local.invalid_ownership_values)))}."
    }

    precondition {
      condition     = length(local.invalid_requested_agency_managed_project_keys) == 0
      error_message = "project_requests_json enables agency-managed blueprints that are not portal-managed in this account: ${join(", ", sort(tolist(local.invalid_requested_agency_managed_project_keys)))}."
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

  name                          = "${local.workspace_prefix}-${each.key}"
  description                   = "Project deployer workspace for ${var.client_id} ${var.environment} ${each.key}."
  allow_destroy_plan            = false
  auto_apply                    = false
  speculative_enabled           = true
  global_remote_state           = length([for p, proj in local.enabled_projects : p if contains(proj.dependencies, each.key)]) > 0
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

    precondition {
      condition     = each.key != "lambda" || !contains(keys(local.enabled_projects[each.key].inputs), "lambda_config_json") || can(keys(local.enabled_projects[each.key].inputs["lambda_config_json"]))
      error_message = "Project 'lambda' input 'lambda_config_json' must be a JSON object, not a quoted JSON string."
    }

    precondition {
      condition     = each.key != "api" || !contains(keys(local.enabled_projects[each.key].inputs), "api_config_json") || can(keys(local.enabled_projects[each.key].inputs["api_config_json"]))
      error_message = "Project 'api' input 'api_config_json' must be a JSON object, not a quoted JSON string."
    }

    precondition {
      condition     = each.key != "dns" || !contains(keys(local.enabled_projects[each.key].inputs), "dns_config_json") || can(keys(local.enabled_projects[each.key].inputs["dns_config_json"]))
      error_message = "Project 'dns' input 'dns_config_json' must be a JSON object, not a quoted JSON string."
    }

    precondition {
      condition     = each.key != "secrets" || !contains(keys(local.enabled_projects[each.key].inputs), "secrets_config_json") || can(keys(local.enabled_projects[each.key].inputs["secrets_config_json"]))
      error_message = "Project 'secrets' input 'secrets_config_json' must be a JSON object, not a quoted JSON string."
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
