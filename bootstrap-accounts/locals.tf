# Stage 1: derive normalized client_id per account key (avoids repeating the
# replace/lower expression in both the top-level fields and the metadata map).
locals {
  _client_ids = {
    for k, account in var.accounts :
    k => lower(replace(replace(coalesce(account.client_id, account.product_name), "_", "-"), " ", "-"))
  }

  # Shared OIDC role name — change here to rename across all workspaces.
  _oidc_role_name = "TerraformDeployRole"
}

# Stage 2: full account normalization and all derived maps.
locals {
  normalized_accounts = {
    for k, account in var.accounts : k => {
      account_id                  = account.account_id
      client_id                   = local._client_ids[k]
      account_name                = try(account.account_name, account.account_id)
      env                         = lower(try(account.env, "dev"))
      product_name                = try(account.product_name, "platform")
      region                      = try(account.region, "us-east-1")
      security_tier               = lower(try(account.security_tier, "standard"))
      services                    = coalescelist(try(account.services, null), [])
      service_family              = lower(try(account.service_family, "platform"))
      description                 = try(account.description, "Terraform deployment for ${local._client_ids[k]} ${lower(try(account.env, "dev"))} (${account.account_id}).")
      working_directory           = try(account.working_directory, "workspaces/account-bootstrap")
      vcs_repo_identifier         = try(account.vcs_repo_identifier, "bootstrap")
      service_vcs_repo_identifier = try(account.service_vcs_repo_identifier, null)
      workspace_tags              = coalescelist(try(account.workspace_tags, null), [])
      service_workspace_variables = try({
        for service_name, vars in account.service_workspace_variables :
        service_name => try({
          for key, value in vars :
          key => value
        }, {})
      }, {})
      workspace_class = "bootstrap-account"
      metadata = {
        client_id         = local._client_ids[k]
        aws_account_id    = account.account_id
        aws_account_name  = try(account.account_name, account.account_id)
        environment       = lower(try(account.env, "dev"))
        aws_region        = try(account.region, "us-east-1")
        security_tier     = lower(try(account.security_tier, "standard"))
        service_family    = lower(try(account.service_family, "platform"))
        selected_services = jsonencode(coalescelist(try(account.services, null), []))
      }
    }
  }

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

  # ── Per-service workspace map ─────────────────────────────────────────────
  # Defaults to the test roots that exist in this repo. Real service repos can
  # extend or replace this via var.service_working_dirs.
  service_working_dirs = var.service_working_dirs

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

  # Flattened map: "{account-key}-{service}" → { account, service }
  # Service workspace creation is opt-in: only accounts with
  # service_vcs_repo_identifier set will get service workspaces.
  service_accounts = {
    for pair in flatten([
      for k, account in local.normalized_accounts : [
        for svc in account.services : {
          key         = "${k}-${svc}"
          account_key = k
          account     = account
          service     = svc
        }
        if svc != "account-bootstrap" && account.service_vcs_repo_identifier != null
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
      lookup(local.service_manual_required_variable_keys, pair.service, toset([])),
      toset(keys(lookup(pair.account.service_workspace_variables, pair.service, {}))),
    )
  }

  # ── Unified variable-set attachment map (bootstrap + team + service) ──────
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
    # team — global
    local.bootstrap_global_variable_set_id == null ? {} : {
      for k, account in local.normalized_accounts :
      "team:${k}:global" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
    },
    # team — environment
    {
      for k, account in local.normalized_accounts :
      "team:${k}:environment" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = local.environment_variable_set_ids[account.env]
      }
      if contains(keys(local.environment_variable_set_ids), account.env)
    },
    # team — security tier
    {
      for k, account in local.normalized_accounts :
      "team:${k}:security-tier" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = local.security_tier_variable_set_ids[account.security_tier]
      }
      if contains(keys(local.security_tier_variable_set_ids), account.security_tier)
    },
    # service — global
    local.bootstrap_global_variable_set_id == null ? {} : {
      for k, pair in local.service_accounts :
      "svc:${k}:global" => {
        workspace_id    = tfe_workspace.service[k].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
    },
    # service — environment
    {
      for k, pair in local.service_accounts :
      "svc:${k}:environment" => {
        workspace_id    = tfe_workspace.service[k].id
        variable_set_id = local.environment_variable_set_ids[pair.account.env]
      }
      if contains(keys(local.environment_variable_set_ids), pair.account.env)
    },
    # service — security tier
    {
      for k, pair in local.service_accounts :
      "svc:${k}:security-tier" => {
        workspace_id    = tfe_workspace.service[k].id
        variable_set_id = local.security_tier_variable_set_ids[pair.account.security_tier]
      }
      if contains(keys(local.security_tier_variable_set_ids), pair.account.security_tier)
    },
  )

  # ── Cross-service workspace name references ───────────────────────────────
  # Injected so workspaces can read outputs from sibling service workspaces
  # without manual HCP UI configuration.
  service_link_variables = merge(
    # secure_baseline_workspace_name — injected for vpc and rds
    {
      for k, pair in local.service_accounts :
      "svc:${k}:secure_baseline_workspace_name" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "secure_baseline_workspace_name"
        value        = "${pair.account.client_id}-${pair.account.env}-secure-baseline"
      }
      if contains(["vpc", "rds"], pair.service)
    },
    # vpc_workspace_name — injected for rds
    {
      for k, pair in local.service_accounts :
      "svc:${k}:vpc_workspace_name" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "vpc_workspace_name"
        value        = "${pair.account.client_id}-${pair.account.env}-vpc"
      }
      if pair.service == "rds"
    },
  )

  # ── Per-service config variables — plain strings (hcl = false) ───────────
  service_config_variables = merge([
    for k, pair in local.service_accounts : {
      for var_key, var_value in lookup(pair.account.services_config, pair.service, {}) :
      "svc:${k}:${var_key}" => {
        workspace_id = tfe_workspace.service[k].id
        key          = var_key
        value        = var_value
      }
    }
  ]...)

  # ── Per-service config variables — HCL expressions (hcl = true) ──────────
  # Use for list(string) / map variables. Values must be valid HCL expressions,
  # e.g. ["us-east-1a", "us-east-1b"] for a list.
  service_config_hcl_variables = merge([
    for k, pair in local.service_accounts : {
      for var_key, var_value in lookup(pair.account.services_config_hcl, pair.service, {}) :
      "svc:${k}:${var_key}" => {
        workspace_id = tfe_workspace.service[k].id
        key          = var_key
        value        = var_value
      }
    }
  ]...)

  # ── Unified metadata variables (bootstrap + team + service) ──────────────
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
    local.service_link_variables,
    local.service_config_variables,
  )

  # ── Unified OIDC env variables (bootstrap + team + service) ──────────────
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
      for k, account in local.normalized_accounts :
      "team:${k}:TFC_AWS_PROVIDER_AUTH" => {
        workspace_id = tfe_workspace.team[k].id
        key          = "TFC_AWS_PROVIDER_AUTH"
        value        = "true"
      }
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:TFC_AWS_RUN_ROLE_ARN" => {
        workspace_id = tfe_workspace.team[k].id
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
      "svc:${k}:secure_baseline_workspace_name" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "secure_baseline_workspace_name"
        value        = jsonencode("${pair.account_key}-secure-baseline")
      }
      if contains(lookup(local.service_dependency_requirements, pair.service, toset([])), "secure-baseline")
    },
    {
      for k, pair in local.service_accounts :
      "svc:${k}:vpc_workspace_name" => {
        workspace_id = tfe_workspace.service[k].id
        key          = "vpc_workspace_name"
        value        = jsonencode("${pair.account_key}-vpc")
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
