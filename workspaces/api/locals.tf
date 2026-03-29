# ── Decode configuration ────────────────────────────────────────────────────────
locals {
  config      = var.api_config_json
  name_prefix = "${var.client_id}-${var.environment}"

  # Sub-configs — each section is optional; defaults disable the component
  gw          = try(local.config.gateway, { enabled = false })
  lambdas     = try(local.config.lambdas, {})
  artifacts   = try(local.config.artifacts, { bucket = "", key_prefix = "", version = "" })
  db_cfg      = try(local.config.database, { proxy_enabled = false })
  uploads_cfg = try(local.config.uploads, { enabled = false })

  configured_artifacts_bucket     = trimspace(try(local.artifacts.bucket, ""))
  configured_artifacts_key_prefix = trimspace(try(local.artifacts.key_prefix, ""))
  configured_artifacts_version    = trimspace(try(local.artifacts.version, ""))
  create_artifacts_bucket         = try(local.artifacts.create_bucket, false)
  upload_seed_artifacts           = try(local.artifacts.upload_seed_code, false)

  default_artifacts_bucket_name = local.configured_artifacts_bucket != "" ? local.configured_artifacts_bucket : (
    var.aws_account_id != null && trimspace(var.aws_account_id) != "" ? "${local.name_prefix}-${var.aws_account_id}-api-code" : "${local.name_prefix}-api-code"
  )
  resolved_artifacts_bucket     = local.create_artifacts_bucket ? local.default_artifacts_bucket_name : local.configured_artifacts_bucket
  resolved_artifacts_key_prefix = local.configured_artifacts_key_prefix != "" ? local.configured_artifacts_key_prefix : "api"
  resolved_artifacts_version    = local.configured_artifacts_version
}

# ── Component enable flags ──────────────────────────────────────────────────────
locals {
  gateway_enabled = try(local.config.gateway, null) != null && try(local.gw.enabled, true)
  has_lambdas     = length(local.lambdas) > 0
  proxy_enabled   = try(local.db_cfg.proxy_enabled, false)
  uploads_enabled = try(local.uploads_cfg.enabled, false)

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
  db_iam_username = trimspace(try(local.db_cfg.iam_username, ""))
}

# ── Cross-workspace derived values (conditional) ────────────────────────────────
locals {
  kms_key_arn        = nonsensitive(data.tfe_outputs.secure_baseline.values.kms_key_arn)
  vpc_id             = local.needs_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.vpc_id) : null
  private_subnet_ids = local.needs_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.private_subnet_ids) : []
  db_identifier      = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_identifier) : null
  db_secret_arn      = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_secret_arn) : null
  rds_sg_id          = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.security_group_id) : null
  is_cluster         = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.enable_cluster) : false
  db_resource_id     = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_resource_id) : null
  db_username        = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_username) : null
  db_name            = local.needs_rds ? nonsensitive(data.tfe_outputs.rds[0].values.db_name) : null
}

# ── Per-Lambda environment variables ──────────────────────────────────────────
locals {
  lambda_env_vars = {
    for k, v in local.lambdas : k => merge(
      try(v.environment, {}),
      # DB env vars — IAM auth, no secret exposure
      try(v.needs_db, false) ? {
        DB_PROXY_ENDPOINT = module.rds_proxy[0].proxy_endpoint
        DB_NAME           = local.db_name
        DB_USERNAME       = local.db_iam_username
        DB_AUTH_MODE      = "iam"
      } : {},
      # Uploads env vars for lambdas that need S3 uploads access
      try(v.needs_uploads, false) ? {
        UPLOADS_BUCKET = module.uploads_bucket[0].bucket_id
      } : {},
      # Authorizer env vars for lambdas that serve as API Gateway authorizers
      contains(keys(local.authorizer_lambda_keys), k) ? {
        AUTH_PROVIDERS        = jsonencode(local.authorizer_lambda_keys[k].auth_providers)
        DEFAULT_AUTH_PROVIDER = local.authorizer_lambda_keys[k].default_auth_provider
      } : {},
    )
  }
}

# ── Per-Lambda IAM policy filter ──────────────────────────────────────────────
locals {
  lambdas_with_policies = {
    for k, v in local.lambdas : k => v
    if try(v.needs_db, false) || try(v.needs_uploads, false)
  }

  db_lambda_keys = [for k, v in local.lambdas : k if try(v.needs_db, false)]
}
