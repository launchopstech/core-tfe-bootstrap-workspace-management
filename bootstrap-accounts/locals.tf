locals {
  normalized_accounts = {
    for k, account in var.accounts : k => {
      account_id          = account.account_id
      client_id           = lower(replace(replace(try(account.client_id, account.product_name), "_", "-"), " ", "-"))
      account_name        = try(account.account_name, account.account_id)
      env                 = lower(try(account.env, "dev"))
      product_name        = try(account.product_name, "platform")
      region              = try(account.region, "us-east-1")
      security_tier       = lower(try(account.security_tier, "standard"))
      services            = try(account.services, [])
      service_family      = lower(try(account.service_family, "platform"))
      description         = try(account.description, "Terraform deployment for ${try(account.client_id, account.product_name)} ${try(account.env, "dev")} (${account.account_id}).")
      working_directory   = try(account.working_directory, "workspaces/account-bootstrap")
      vcs_repo_identifier = try(account.vcs_repo_identifier, "bootstrap")
      workspace_tags      = try(account.workspace_tags, [])
      workspace_class     = "bootstrap-account"
      metadata = {
        client_id         = lower(replace(replace(try(account.client_id, account.product_name), "_", "-"), " ", "-"))
        aws_account_id    = account.account_id
        aws_account_name  = try(account.account_name, account.account_id)
        environment       = lower(try(account.env, "dev"))
        aws_region        = try(account.region, "us-east-1")
        security_tier     = lower(try(account.security_tier, "standard"))
        service_family    = lower(try(account.service_family, "platform"))
        selected_services = jsonencode(try(account.services, []))
        workspace_class   = "bootstrap-account"
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

  workspace_variable_sets = merge(
    {
      for k, account in local.normalized_accounts :
      "${k}:global" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
      if local.bootstrap_global_variable_set_id != null
    },
    {
      for k, account in local.normalized_accounts :
      "${k}:environment" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = lookup(local.environment_variable_set_ids, account.env, null)
      }
      if lookup(local.environment_variable_set_ids, account.env, null) != null
    },
    {
      for k, account in local.normalized_accounts :
      "${k}:security-tier" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = lookup(local.security_tier_variable_set_ids, account.security_tier, null)
      }
      if lookup(local.security_tier_variable_set_ids, account.security_tier, null) != null
    },
    {
      for k, account in local.normalized_accounts :
      "${k}:secrets" => {
        workspace_id    = tfe_workspace.bootstrap_account[k].id
        variable_set_id = local.control_plane_secrets_variable_set_id
      }
      if local.control_plane_secrets_variable_set_id != null
    },
  )

  workspace_metadata_variables = length(local.normalized_accounts) == 0 ? {} : merge([
    for k, account in local.normalized_accounts : {
      for key, value in account.metadata : "${k}:${key}" => {
        workspace_id = tfe_workspace.bootstrap_account[k].id
        key          = key
        value        = value
      }
    }
  ]...)

  # ── Team workspace variable sets ──────────────────────────────────────────
  team_workspace_variable_sets = merge(
    {
      for k, account in local.normalized_accounts :
      "team:${k}:global" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
      if local.bootstrap_global_variable_set_id != null
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:environment" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = lookup(local.environment_variable_set_ids, account.env, null)
      }
      if lookup(local.environment_variable_set_ids, account.env, null) != null
    },
    {
      for k, account in local.normalized_accounts :
      "team:${k}:security-tier" => {
        workspace_id    = tfe_workspace.team[k].id
        variable_set_id = lookup(local.security_tier_variable_set_ids, account.security_tier, null)
      }
      if lookup(local.security_tier_variable_set_ids, account.security_tier, null) != null
    },
  )

  team_metadata_variables = length(local.normalized_accounts) == 0 ? {} : merge([
    for k, account in local.normalized_accounts : {
      for key, value in account.metadata : "team:${k}:${key}" => {
        workspace_id = tfe_workspace.team[k].id
        key          = key
        value        = value
      }
    }
  ]...)

  # ── OIDC dynamic credentials (environment variables) ──────────────────────
  # TFC_AWS_PROVIDER_AUTH and TFC_AWS_RUN_ROLE_ARN are required by the HCP
  # Terraform AWS provider to authenticate via OIDC dynamic credentials.
  # The role ARN is derived from account.account_id, not the map key.
  bootstrap_oidc_env_variables = length(local.normalized_accounts) == 0 ? {} : merge([
    for k, account in local.normalized_accounts : {
      "${k}:TFC_AWS_PROVIDER_AUTH" = {
        workspace_id = tfe_workspace.bootstrap_account[k].id
        key          = "TFC_AWS_PROVIDER_AUTH"
        value        = "true"
      }
      "${k}:TFC_AWS_RUN_ROLE_ARN" = {
        workspace_id = tfe_workspace.bootstrap_account[k].id
        key          = "TFC_AWS_RUN_ROLE_ARN"
        value        = "arn:aws:iam::${account.account_id}:role/TerraformDeployRole"
      }
    }
  ]...)

  team_oidc_env_variables = length(local.normalized_accounts) == 0 ? {} : merge([
    for k, account in local.normalized_accounts : {
      "team:${k}:TFC_AWS_PROVIDER_AUTH" = {
        workspace_id = tfe_workspace.team[k].id
        key          = "TFC_AWS_PROVIDER_AUTH"
        value        = "true"
      }
      "team:${k}:TFC_AWS_RUN_ROLE_ARN" = {
        workspace_id = tfe_workspace.team[k].id
        key          = "TFC_AWS_RUN_ROLE_ARN"
        value        = "arn:aws:iam::${account.account_id}:role/TerraformDeployRole"
      }
    }
  ]...)
}
