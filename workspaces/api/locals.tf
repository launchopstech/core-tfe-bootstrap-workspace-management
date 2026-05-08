# ── Decode configuration ────────────────────────────────────────────────────────
locals {
  config      = var.api_config_json
  name_prefix = var.env_suffix_mode ? var.client_id : "${var.client_id}-${var.environment}"
  name_suffix = var.env_suffix_mode ? "-${var.environment}" : ""

  # Sub-configs — each section is optional; defaults disable the component
  gw          = try(local.config.gateway, { enabled = false })
  lambdas     = try(local.config.lambdas, {})
  artifacts   = try(local.config.artifacts, { bucket = "", key_prefix = "", version = "" })
  db_cfg      = try(local.config.database, { proxy_enabled = false })
  uploads_cfg = try(local.config.uploads, { enabled = false })
  waf_cfg     = try(local.gw.waf, { enabled = false })

  configured_artifacts_bucket       = trimspace(try(local.artifacts.bucket, ""))
  configured_artifacts_key_prefix   = trimspace(try(local.artifacts.key_prefix, ""))
  configured_artifacts_version      = trimspace(try(local.artifacts.version, ""))
  normalized_aws_account_id         = try(trimspace(var.aws_account_id), "")
  normalized_dns_workspace_name     = try(trimspace(var.dns_workspace_name), "")
  normalized_waf_workspace_name     = try(trimspace(var.waf_workspace_name), "")
  normalized_secrets_workspace_name = try(trimspace(var.secrets_workspace_name), "")
  create_artifacts_bucket           = try(local.artifacts.create_bucket, false)
  custom_domains                    = try(local.gw.custom_domains, {})

  # CI/CD writes artifacts.functions for lambdas backed by externally-built ZIPs.
  # That list takes precedence over stale upload_seed_code flags.
  externally_deployed_lambda_keys = toset([
    for lambda_key in try(local.artifacts.functions, []) :
    trimspace(lambda_key)
    if trimspace(lambda_key) != ""
  ])
  lambda_uses_seed_artifact = {
    for lambda_key, lambda_cfg in local.lambdas :
    lambda_key => try(lambda_cfg.upload_seed_code, false) && !contains(local.externally_deployed_lambda_keys, lambda_key)
  }

  lambda_secret_refs = {
    for lambda_key, lambda_cfg in local.lambdas : lambda_key => {
      for env_name, secret_key in try(lambda_cfg.env_vars, {}) :
      trimspace(env_name) => trimspace(secret_key)
      if trimspace(env_name) != "" && trimspace(secret_key) != ""
    }
  }

  default_artifacts_bucket_name = local.configured_artifacts_bucket != "" ? local.configured_artifacts_bucket : (
    local.normalized_aws_account_id != "" ? "${local.name_prefix}-${local.normalized_aws_account_id}-api-code${local.name_suffix}" : "${local.name_prefix}-api-code${local.name_suffix}"
  )
  resolved_artifacts_bucket      = local.create_artifacts_bucket ? local.default_artifacts_bucket_name : local.configured_artifacts_bucket
  resolved_artifacts_key_prefix  = local.configured_artifacts_key_prefix != "" ? local.configured_artifacts_key_prefix : "api"
  resolved_artifacts_version     = local.configured_artifacts_version
  normalized_custom_domain_names = [for key, domain in local.custom_domains : lower(trimspace(try(domain.domain_name, "")))]
}

# ── Component enable flags ──────────────────────────────────────────────────────
locals {
  gateway_enabled    = try(local.config.gateway, null) != null && try(local.gw.enabled, true)
  has_lambdas        = length(local.lambdas) > 0
  has_custom_domains = length(local.custom_domains) > 0
  proxy_enabled      = try(local.db_cfg.proxy_enabled, false)
  uploads_enabled    = try(local.uploads_cfg.enabled, false)
  waf_enabled        = local.gateway_enabled && try(local.waf_cfg.enabled, false)
  custom_domains_need_dns = try(anytrue([
    for key, domain in local.custom_domains : trimspace(try(domain.hosted_zone_id, "")) == ""
  ]), false)
  use_dns_workspace = local.custom_domains_need_dns && local.normalized_dns_workspace_name != ""
  use_waf_workspace = local.waf_enabled && local.normalized_waf_workspace_name != ""
  has_lambda_secret_refs = try(anytrue([
    for lambda_key, secret_refs in local.lambda_secret_refs : length(keys(secret_refs)) > 0
  ]), false)
  use_secrets_workspace = local.has_lambda_secret_refs && local.normalized_secrets_workspace_name != ""

  # needs_db implies VPC attachment — DB Lambdas always go through RDS Proxy in VPC
  needs_vpc = local.has_lambdas && anytrue([for k, v in local.lambdas : try(v.needs_vpc, false) || try(v.needs_db, false)]) || local.proxy_enabled
  needs_rds = local.has_lambdas && anytrue([for k, v in local.lambdas : try(v.needs_db, false)]) || local.proxy_enabled

  # Authorizer lambda_key → authorizer config lookup
  authorizer_lambda_keys = local.gateway_enabled ? {
    for ak, av in try(local.gw.authorizers, {}) : av.lambda_key => av
  } : {}

  # IAM username for rds-db:connect. This must be an existing database role
  # that is allowed to authenticate through RDS IAM; we validate it when any
  # Lambda declares needs_db = true.
  db_iam_username        = trimspace(try(local.db_cfg.iam_username, ""))
  migration_iam_username = trimspace(try(local.db_cfg.migration_iam_username, "migrator"))
  lambda_db_iam_usernames = {
    for k, v in local.lambdas : k => try(trimspace(v.db_iam_username), local.db_iam_username)
  }
}

# ── Cross-workspace derived values (conditional) ────────────────────────────────
locals {
  kms_key_arn           = nonsensitive(data.tfe_outputs.secure_baseline.values.kms_key_arn)
  vpc_id                = local.needs_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.vpc_id) : null
  private_subnet_ids    = local.needs_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.private_subnet_ids) : []
  db_identifier         = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_identifier) : null
  db_secret_arn         = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_secret_arn) : null
  db_instance_endpoint  = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_instance_endpoint) : null
  rds_sg_id             = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.security_group_id) : null
  is_cluster            = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.enable_cluster) : false
  db_resource_id        = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_resource_id) : null
  db_username           = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_username) : null
  db_name               = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_name) : null
  dns_hosted_zone_id    = local.use_dns_workspace ? try(nonsensitive(data.tfe_outputs.dns[0].values.hosted_zone_id), null) : null
  waf_web_acl_arn       = local.use_waf_workspace ? try(nonsensitive(data.tfe_outputs.waf[0].values.web_acl_arn), null) : null
  waf_scope             = local.use_waf_workspace ? try(nonsensitive(data.tfe_outputs.waf[0].values.scope), null) : null
  waf_attachment_mode   = local.use_waf_workspace ? try(nonsensitive(data.tfe_outputs.waf[0].values.attachment_mode), null) : null
  secret_arns_by_key    = local.use_secrets_workspace ? try(nonsensitive(data.tfe_outputs.secrets[0].values.secret_arns), {}) : {}
  secrets_with_versions = local.use_secrets_workspace ? try(nonsensitive(toset(data.tfe_outputs.secrets[0].values.secrets_with_versions)), toset([])) : toset([])
}

# ── Custom domain resolution ───────────────────────────────────────────────────
locals {
  resolved_custom_domains = {
    for key, domain in local.custom_domains : key => {
      domain_name = trimspace(try(domain.domain_name, ""))
      hosted_zone_id = trimspace(try(domain.hosted_zone_id, "")) != "" ? upper(trimspace(try(domain.hosted_zone_id, ""))) : (
        local.dns_hosted_zone_id != null ? upper(trimspace(local.dns_hosted_zone_id)) : ""
      )
      base_path = trimspace(try(domain.base_path, ""))
    }
  }
}

# ── Secrets resolution ────────────────────────────────────────────────────────
locals {
  lambda_missing_secret_keys = {
    for lambda_key, secret_refs in local.lambda_secret_refs :
    lambda_key => setsubtract(
      toset(values(secret_refs)),
      toset(keys(local.secret_arns_by_key)),
    )
  }

  # Inject secret ARNs as env var values — Lambda resolves actual values at runtime
  # via GetSecretValue. This keeps secret material out of Terraform state and ensures
  # out-of-band rotations (put-secret-value) propagate without workspace re-apply.
  # try() guards the lookup so a fat-fingered key produces the precondition's friendly
  # "unknown secret key" error instead of a raw "Invalid index" panic.
  lambda_secret_env_vars = {
    for lambda_key, secret_refs in local.lambda_secret_refs : lambda_key => {
      for env_name, secret_key in secret_refs :
      env_name => try(local.secret_arns_by_key[secret_key], "")
    }
  }
}

# ── Per-Lambda environment variables ──────────────────────────────────────────
locals {
  lambda_env_vars = {
    for k, v in local.lambdas : k => merge(
      try(v.environment, {}),
      try(local.lambda_secret_env_vars[k], {}),
      # DB env vars — IAM auth, no secret exposure
      try(v.needs_db, false) ? {
        DB_PROXY_ENDPOINT = module.rds_proxy[0].proxy_endpoint
        DB_NAME           = local.db_name
        DB_USERNAME       = local.lambda_db_iam_usernames[k]
        DB_AUTH_MODE      = "iam"
      } : {},
      try(v.needs_db_admin, false) ? {
        DB_ADMIN_HOST       = local.db_instance_endpoint
        DB_ADMIN_SECRET_ARN = local.db_secret_arn
        DB_ADMIN_USERNAME   = local.db_username
        DB_APP_USERNAME     = local.db_iam_username
        DB_MIGRATOR_HOST    = local.db_instance_endpoint
        DB_MIGRATOR_USERNAME = (
          local.lambda_db_iam_usernames[k] != ""
          ? local.lambda_db_iam_usernames[k]
          : local.migration_iam_username
        )
        DB_APP_USER_SECRET_ARN = local.proxy_enabled ? aws_secretsmanager_secret.db_app_user[0].arn : ""
      } : {},
      # Uploads env vars for lambdas that need S3 uploads access
      try(v.needs_uploads, false) ? {
        UPLOADS_BUCKET = module.uploads_bucket[0].bucket_id
      } : {},
    )
  }
}

# ── Per-Lambda IAM policy filter ──────────────────────────────────────────────
locals {
  lambdas_with_policies = {
    for k, v in local.lambdas : k => v
    if try(v.needs_db, false) || try(v.needs_db_admin, false) || try(v.needs_uploads, false) || length(try(local.lambda_secret_refs[k], {})) > 0
  }

  db_lambda_keys       = [for k, v in local.lambdas : k if try(v.needs_db, false)]
  db_admin_lambda_keys = [for k, v in local.lambdas : k if try(v.needs_db_admin, false)]
}
