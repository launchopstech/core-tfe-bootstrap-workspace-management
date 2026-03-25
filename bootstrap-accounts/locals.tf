# Stage 1: derive normalized client_id per account key and shared constants.
locals {
  _client_ids = {
    for k, account in var.accounts :
    k => lower(replace(replace(coalesce(try(account.client_id, null), try(account.product_name, null), ""), "_", "-"), " ", "-"))
  }

  # Shared OIDC role name — change here to rename across all workspaces.
  _oidc_role_name = "TerraformDeployRole"

  # MVP portal support is intentionally narrow: clients can self-service only
  # these blueprints, while agency-managed workspaces stay under control-plane
  # ownership.
  _client_requestable_services = toset(["vpc", "rds"])
  _agency_managed_services     = toset(["secure-baseline"])

  service_dependency_requirements = {
    "secure-baseline" = toset([])
    "vpc"             = toset(["secure-baseline"])
    "rds"             = toset(["secure-baseline", "vpc"])
  }

  # Inputs that must be supplied manually when opting into managed service
  # workspaces. Derived dependency workspace names are injected automatically.
  service_manual_required_variable_keys = {
    "secure-baseline" = toset([])
    "vpc"             = toset(["cidr_block", "azs", "private_subnets", "public_subnets"])
    "rds"             = toset([])
  }
}

# Stage 2: full account normalization and all derived maps.
locals {
  normalized_accounts = {
    for k, account in var.accounts : k => {
      account_key                 = k
      account_id                  = account.account_id
      client_id                   = local._client_ids[k]
      workspace_prefix            = "${local._client_ids[k]}-${lower(try(account.env, "dev"))}"
      account_name                = try(account.account_name, account.account_id)
      env                         = lower(try(account.env, "dev"))
      product_name                = try(account.product_name, "platform")
      region                      = try(account.region, "us-east-1")
      security_tier               = lower(try(account.security_tier, "standard"))
      services                    = try(tolist(account.services), [])
      service_family              = lower(try(account.service_family, "platform"))
      client_admin_team_name      = try(trimspace(account.client_admin_team_name), "")
      description                 = try(account.description, "Terraform deployment for ${local._client_ids[k]} ${lower(try(account.env, "dev"))} (${account.account_id}).")
      working_directory           = try(account.working_directory, "workspaces/account-bootstrap")
      portal_working_directory    = try(account.portal_working_directory, "workspaces/account-portal")
      vcs_repo_identifier         = try(account.vcs_repo_identifier, "bootstrap")
      service_vcs_repo_identifier = try(trimspace(account.service_vcs_repo_identifier), "") != "" ? trimspace(account.service_vcs_repo_identifier) : null
      project_vcs_repo_identifier = try(trimspace(account.service_vcs_repo_identifier), "") != "" ? trimspace(account.service_vcs_repo_identifier) : try(account.vcs_repo_identifier, "bootstrap")
      workspace_tags              = try(tolist(account.workspace_tags), [])
      service_workspace_variables = try({
        for service_name, vars in account.service_workspace_variables :
        service_name => try({
          for key, value in vars :
          key => value
        }, {})
      }, {})
      seeded_project_requests = {
        projects = {
          for svc in try(tolist(account.services), []) :
          svc => merge(
            {
              enabled = true
              inputs = lookup(try({
                for service_name, vars in account.service_workspace_variables :
                service_name => try({
                  for key, value in vars :
                  key => value
                }, {})
              }, {}), svc, {})
            },
            svc == "rds" ? { depends_on = ["vpc"] } : {}
          )
          if contains(local._client_requestable_services, svc)
        }
      }
      metadata = {
        client_id         = local._client_ids[k]
        aws_account_id    = account.account_id
        aws_account_name  = try(account.account_name, account.account_id)
        environment       = lower(try(account.env, "dev"))
        aws_region        = try(account.region, "us-east-1")
        security_tier     = lower(try(account.security_tier, "standard"))
        service_family    = lower(try(account.service_family, "platform"))
        selected_services = jsonencode(try(tolist(account.services), []))
      }
    }
  }

  client_admin_team_names = toset([
    for account in values(local.normalized_accounts) : account.client_admin_team_name
    if account.client_admin_team_name != ""
  ])

  bootstrap_global_variable_set_id = try(
    nonsensitive(data.tfe_outputs.bootstrap_variable_sets.values.bootstrap_global_variable_set_id),
    null,
  )
  environment_variable_set_ids = try(
    nonsensitive(data.tfe_outputs.bootstrap_variable_sets.values.environment_variable_set_ids),
    {},
  )
  security_tier_variable_set_ids = try(
    nonsensitive(data.tfe_outputs.bootstrap_variable_sets.values.security_tier_variable_set_ids),
    {},
  )
  control_plane_secrets_variable_set_id = try(
    nonsensitive(data.tfe_outputs.bootstrap_variable_sets.values.control_plane_secrets_variable_set_id),
    null,
  )

  # Defaults to the test roots that exist in this repo. Real service repos can
  # extend or replace these working directories later.
  service_working_dirs = var.service_working_dirs

  account_seed_requested_services = {
    for k, account in local.normalized_accounts :
    k => toset([
      for svc in account.services : svc
      if contains(local._client_requestable_services, svc)
    ])
  }

  account_seed_missing_dependencies = {
    for k, account in local.normalized_accounts :
    k => toset(flatten([
      for svc in local.account_seed_requested_services[k] :
      tolist(setsubtract(
        lookup(local.service_dependency_requirements, svc, toset([])),
        toset(account.services),
      ))
    ]))
  }

  account_seed_missing_required_variables = {
    for k, account in local.normalized_accounts :
    k => toset(flatten([
      for svc in local.account_seed_requested_services[k] :
      tolist(setsubtract(
        setunion(
          lookup(local.service_manual_required_variable_keys, svc, toset([])),
          svc == "vpc" && contains(account.services, "rds") ? toset(["database_subnets"]) : toset([]),
        ),
        toset(keys(lookup(account.service_workspace_variables, svc, {}))),
      ))
    ]))
  }

  # Flattened map: "{workspace-prefix}-{service}" → { account, service }.
  # Only agency-managed project workspaces are created directly here; client
  # requestable blueprints are seeded into the account portal.
  service_accounts = {
    for pair in flatten([
      for k, account in local.normalized_accounts : [
        for svc in account.services : {
          key         = "${account.workspace_prefix}-${svc}"
          account_key = k
          account     = account
          service     = svc
        }
        if contains(local._agency_managed_services, svc)
      ]
    ]) : pair.key => pair
  }

  service_missing_dependencies = {
    for k, pair in local.service_accounts :
    k => setsubtract(
      lookup(local.service_dependency_requirements, pair.service, toset([])),
      toset(pair.account.services),
    )
  }

  service_missing_required_variables = {
    for k, pair in local.service_accounts :
    k => setsubtract(
      setunion(
        lookup(local.service_manual_required_variable_keys, pair.service, toset([])),
        pair.service == "vpc" && contains(pair.account.services, "rds") ? toset(["database_subnets"]) : toset([]),
      ),
      toset(keys(lookup(pair.account.service_workspace_variables, pair.service, {}))),
    )
  }

  # ── Unified variable-set attachment map (bootstrap + account portal + agency project) ──
  all_workspace_variable_sets = merge(
    # bootstrap — global
    local.bootstrap_global_variable_set_id == null ? {} : {
      for k, account in local.normalized_accounts :
      "bootstrap:${k}:global" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
    },
    # bootstrap — environment
    {
      for k, account in local.normalized_accounts :
      "bootstrap:${k}:environment" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = local.environment_variable_set_ids[account.env]
      }
      if contains(keys(local.environment_variable_set_ids), account.env)
    },
    # bootstrap — security tier
    {
      for k, account in local.normalized_accounts :
      "bootstrap:${k}:security-tier" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = local.security_tier_variable_set_ids[account.security_tier]
      }
      if contains(keys(local.security_tier_variable_set_ids), account.security_tier)
    },
    # bootstrap — secrets
    local.control_plane_secrets_variable_set_id == null ? {} : {
      for k, account in local.normalized_accounts :
      "bootstrap:${k}:secrets" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = local.control_plane_secrets_variable_set_id
      }
    },
    # account portal — global
    local.bootstrap_global_variable_set_id == null ? {} : {
      for k, account in local.normalized_accounts :
      "team:${k}:global" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
    },
    # account portal — environment
    {
      for k, account in local.normalized_accounts :
      "team:${k}:environment" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = local.environment_variable_set_ids[account.env]
      }
      if contains(keys(local.environment_variable_set_ids), account.env)
    },
    # account portal — security tier
    {
      for k, account in local.normalized_accounts :
      "team:${k}:security-tier" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = local.security_tier_variable_set_ids[account.security_tier]
      }
      if contains(keys(local.security_tier_variable_set_ids), account.security_tier)
    },
    # agency project — global
    local.bootstrap_global_variable_set_id == null ? {} : {
      for k, pair in local.service_accounts :
      "svc:${k}:global" => {
        workspace_id    = tfe_workspace.service[k].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
    },
    # agency project — environment
    {
      for k, pair in local.service_accounts :
      "svc:${k}:environment" => {
        workspace_id    = tfe_workspace.service[k].id
        variable_set_id = local.environment_variable_set_ids[pair.account.env]
      }
      if contains(keys(local.environment_variable_set_ids), pair.account.env)
    },
    # agency project — security tier
    {
      for k, pair in local.service_accounts :
      "svc:${k}:security-tier" => {
        workspace_id    = tfe_workspace.service[k].id
        variable_set_id = local.security_tier_variable_set_ids[pair.account.security_tier]
      }
      if contains(keys(local.security_tier_variable_set_ids), pair.account.security_tier)
    },
  )

  # ── Unified metadata variables (bootstrap + account portal + agency project) ─────────
  all_metadata_variables = merge(
    merge([
      for k, account in local.normalized_accounts : {
        for key, value in account.metadata : "bootstrap:${k}:${key}" => {
          workspace_id = tfe_workspace.bootstrap_account[k].id
          key          = key
          value        = value
        }
      }
    ]...),
    merge([
      for k, account in local.normalized_accounts : {
        for key, value in account.metadata : "team:${k}:${key}" => {
          workspace_id = tfe_workspace.team[k].id
          key          = key
          value        = value
        }
      }
    ]...),
    merge([
      for k, pair in local.service_accounts : {
        for key, value in pair.account.metadata : "svc:${k}:${key}" => {
          workspace_id = tfe_workspace.service[k].id
          key          = key
          value        = value
        }
      }
    ]...),
  )

  account_portal_contract_variables = merge(
    {
      for k, account in local.normalized_accounts :
      "team:${k}:organization" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "organization"
        value        = var.organization
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:project_id" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "project_id"
        value        = var.team_project_id
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:project_vcs_repo_identifier" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "project_vcs_repo_identifier"
        value        = account.project_vcs_repo_identifier
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:project_vcs_oauth_token_id" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "project_vcs_oauth_token_id"
        value        = var.aws_core_oauth_token_id
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:project_requests_json" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "project_requests_json"
        value        = jsonencode(account.seeded_project_requests)
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:terraform_run_role_arn" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "terraform_run_role_arn"
        value        = "arn:aws:iam::${account.account_id}:role/${local._oidc_role_name}"
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:terraform_version" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "terraform_version"
        value        = var.terraform_version
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:notification_emails_json" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "notification_emails_json"
        value        = jsonencode(var.notification_emails)
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:client_admin_team_name" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "client_admin_team_name"
        value        = account.client_admin_team_name
      }
      if account.client_admin_team_name != ""
    },
    local.bootstrap_global_variable_set_id == null ? {} : {
      for k, account in local.normalized_accounts :
      "team:${k}:bootstrap_global_variable_set_id" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "bootstrap_global_variable_set_id"
        value        = local.bootstrap_global_variable_set_id
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:environment_variable_set_id" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "environment_variable_set_id"
        value        = local.environment_variable_set_ids[account.env]
      }
      if contains(keys(local.environment_variable_set_ids), account.env)
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:security_tier_variable_set_id" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "security_tier_variable_set_id"
        value        = local.security_tier_variable_set_ids[account.security_tier]
      }
      if contains(keys(local.security_tier_variable_set_ids), account.security_tier)
    },
  )

  # OIDC dynamic credentials are required only for workspaces that run against
  # AWS directly (bootstrap + agency-managed project workspaces).
  all_oidc_env_variables = merge(
    {
      for k, account in local.normalized_accounts :
      "bootstrap:${k}:TFC_AWS_PROVIDER_AUTH" => {
        workspace_id = tfe_workspace.bootstrap_account[k].id
        key          = "TFC_AWS_PROVIDER_AUTH"
        value        = "true"
      }
    },
    {
      for k, account in local.normalized_accounts :
      "bootstrap:${k}:TFC_AWS_RUN_ROLE_ARN" => {
        workspace_id = tfe_workspace.bootstrap_account[k].id
        key          = "TFC_AWS_RUN_ROLE_ARN"
        value        = "arn:aws:iam::${account.account_id}:role/${local._oidc_role_name}"
      }
    },
    {
      for k, pair in local.service_accounts :
      "svc:${k}:TFC_AWS_PROVIDER_AUTH" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "TFC_AWS_PROVIDER_AUTH"
        value        = "true"
      }
    },
    {
      for k, pair in local.service_accounts :
      "svc:${k}:TFC_AWS_RUN_ROLE_ARN" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "TFC_AWS_RUN_ROLE_ARN"
        value        = "arn:aws:iam::${pair.account.account_id}:role/${local._oidc_role_name}"
      }
    },
  )

  derived_service_workspace_variables = merge(
    {
      for k, pair in local.service_accounts :
      "svc:${k}:hcp_terraform_organization" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "hcp_terraform_organization"
        value        = jsonencode(var.organization)
      }
      if contains(["vpc", "rds"], pair.service)
    },
    {
      for k, pair in local.service_accounts :
      "svc:${k}:secure_baseline_workspace_name" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "secure_baseline_workspace_name"
        value        = jsonencode("${pair.account.workspace_prefix}-secure-baseline")
      }
      if contains(lookup(local.service_dependency_requirements, pair.service, toset([])), "secure-baseline")
    },
    {
      for k, pair in local.service_accounts :
      "svc:${k}:vpc_workspace_name" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "vpc_workspace_name"
        value        = jsonencode("${pair.account.workspace_prefix}-vpc")
      }
      if contains(lookup(local.service_dependency_requirements, pair.service, toset([])), "vpc")
    },
  )

  service_workspace_input_variables = merge(
    merge([
      for k, pair in local.service_accounts : {
        for key, value in lookup(pair.account.service_workspace_variables, pair.service, {}) :
        "svc:${k}:${key}" => {
          workspace_id = tfe_workspace.service[k].id
          key          = key
          value        = jsonencode(value)
        }
      }
    ]...),
    local.derived_service_workspace_variables,
  )
}
