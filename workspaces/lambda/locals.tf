# ── Decode configuration ────────────────────────────────────────────────────────
locals {
  config = var.lambda_config_json

  function_name_suffix = local.config.function_name_suffix
  function_name        = "${var.client_id}-${var.environment}-${local.function_name_suffix}"

  # Package
  configured_s3_bucket  = trimspace(try(local.config.package.bucket, ""))
  configured_s3_key     = trimspace(try(local.config.package.key, ""))
  create_package_bucket = try(local.config.package.create_bucket, false)
  upload_seed_package   = try(local.config.package.upload_seed_code, false)

  # Runtime
  handler = try(local.config.runtime.handler, "bootstrap")
  runtime = try(local.config.runtime.runtime, "provided.al2023")

  # Performance
  memory_size = try(local.config.performance.memory_mb, 256)
  timeout     = try(local.config.performance.timeout_seconds, 30)

  # Environment variables
  configured_env_vars = try(local.config.environment, {})
  secret_refs = {
    for env_name, secret_key in try(local.config.secret_refs, {}) :
    trimspace(env_name) => trimspace(secret_key)
    if trimspace(env_name) != "" && trimspace(secret_key) != ""
  }
  has_secret_refs = length(keys(local.secret_refs)) > 0

  # Network
  enable_vpc            = try(local.config.network.enabled, false)
  use_secrets_workspace = local.has_secret_refs && trimspace(var.secrets_workspace_name) != ""

  # IAM
  additional_policy_json = try(local.config.iam.additional_policy_json, "")

  default_package_bucket_name = local.configured_s3_bucket != "" ? local.configured_s3_bucket : (
    var.aws_account_id != null && trimspace(var.aws_account_id) != "" ? "${var.client_id}-${var.environment}-${var.aws_account_id}-lambda-code" : "${var.client_id}-${var.environment}-lambda-code"
  )
  resolved_s3_bucket = local.create_package_bucket ? local.default_package_bucket_name : local.configured_s3_bucket
  resolved_s3_key    = local.configured_s3_key != "" ? local.configured_s3_key : "lambda/${local.function_name_suffix}.zip"
}

# ── Cross-workspace derived values ────────────────────────────────────────────
locals {
  kms_key_arn        = nonsensitive(data.tfe_outputs.secure_baseline.values.kms_key_arn)
  vpc_id             = local.enable_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.vpc_id) : null
  subnet_ids         = local.enable_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.private_subnet_ids) : []
  secret_arns_by_key = local.use_secrets_workspace ? try(nonsensitive(data.tfe_outputs.secrets[0].values.secret_arns), {}) : {}
  missing_secret_keys = setsubtract(
    toset(values(local.secret_refs)),
    toset(keys(local.secret_arns_by_key)),
  )
  secret_env_vars = {
    for env_name, secret_key in local.secret_refs :
    env_name => local.secret_arns_by_key[secret_key]
    if contains(keys(local.secret_arns_by_key), secret_key)
  }
  has_resolved_secret_refs = length(keys(local.secret_env_vars)) > 0
  env_vars                 = merge(local.configured_env_vars, local.secret_env_vars)
}
