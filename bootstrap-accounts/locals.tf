locals {
  normalized_accounts = {
    for account_id, account in var.accounts : account_id => {
      client_id           = lower(replace(replace(try(account.client_id, account.product_name), "_", "-"), " ", "-"))
      account_name        = try(account.account_name, account_id)
      env                 = lower(try(account.env, "dev"))
      product_name        = try(account.product_name, "platform")
      region              = try(account.region, "us-east-1")
      security_tier       = lower(try(account.security_tier, "standard"))
      services            = try(account.services, [])
      service_family      = lower(try(account.service_family, "platform"))
      description         = try(account.description, "Terraform deployment to bootstrap the ${try(account.client_id, account.product_name)} ${try(account.env, "dev")}, ${account_id} account.")
      working_directory   = try(account.working_directory, "terraform")
      vcs_repo_identifier = try(account.vcs_repo_identifier, "bootstrap")
      workspace_tags      = try(account.workspace_tags, [])
      workspace_class     = "bootstrap-account"
      metadata = {
        client_id         = lower(replace(replace(try(account.client_id, account.product_name), "_", "-"), " ", "-"))
        aws_account_id    = account_id
        aws_account_name  = try(account.account_name, account_id)
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
      for account_id, account in local.normalized_accounts :
      "${account_id}:global" => {
        workspace_id    = tfe_workspace.bootstrap_account[account_id].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
      if local.bootstrap_global_variable_set_id != null
    },
    {
      for account_id, account in local.normalized_accounts :
      "${account_id}:environment" => {
        workspace_id    = tfe_workspace.bootstrap_account[account_id].id
        variable_set_id = lookup(local.environment_variable_set_ids, account.env, null)
      }
      if lookup(local.environment_variable_set_ids, account.env, null) != null
    },
    {
      for account_id, account in local.normalized_accounts :
      "${account_id}:security-tier" => {
        workspace_id    = tfe_workspace.bootstrap_account[account_id].id
        variable_set_id = lookup(local.security_tier_variable_set_ids, account.security_tier, null)
      }
      if lookup(local.security_tier_variable_set_ids, account.security_tier, null) != null
    },
    {
      for account_id, account in local.normalized_accounts :
      "${account_id}:secrets" => {
        workspace_id    = tfe_workspace.bootstrap_account[account_id].id
        variable_set_id = local.control_plane_secrets_variable_set_id
      }
      if local.control_plane_secrets_variable_set_id != null
    },
  )

  workspace_metadata_variables = length(local.normalized_accounts) == 0 ? {} : merge([
    for account_id, account in local.normalized_accounts : {
      for key, value in account.metadata : "${account_id}:${key}" => {
        workspace_id = tfe_workspace.bootstrap_account[account_id].id
        key          = key
        value        = value
      }
    }
  ]...)

  # ── Team workspace variable sets ──────────────────────────────────────────
  team_workspace_variable_sets = merge(
    {
      for account_id, account in local.normalized_accounts :
      "team:${account_id}:global" => {
        workspace_id    = tfe_workspace.team[account_id].id
        variable_set_id = local.bootstrap_global_variable_set_id
      }
      if local.bootstrap_global_variable_set_id != null
    },
    {
      for account_id, account in local.normalized_accounts :
      "team:${account_id}:environment" => {
        workspace_id    = tfe_workspace.team[account_id].id
        variable_set_id = lookup(local.environment_variable_set_ids, account.env, null)
      }
      if lookup(local.environment_variable_set_ids, account.env, null) != null
    },
    {
      for account_id, account in local.normalized_accounts :
      "team:${account_id}:security-tier" => {
        workspace_id    = tfe_workspace.team[account_id].id
        variable_set_id = lookup(local.security_tier_variable_set_ids, account.security_tier, null)
      }
      if lookup(local.security_tier_variable_set_ids, account.security_tier, null) != null
    },
  )

  team_metadata_variables = length(local.normalized_accounts) == 0 ? {} : merge([
    for account_id, account in local.normalized_accounts : {
      for key, value in account.metadata : "team:${account_id}:${key}" => {
        workspace_id = tfe_workspace.team[account_id].id
        key          = key
        value        = value
      }
    }
  ]...)
}
