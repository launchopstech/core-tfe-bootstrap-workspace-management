# ── Decode configuration ────────────────────────────────────────────────────────
locals {
  config = jsondecode(var.lambda_config_json)

  function_name_suffix = local.config.function_name_suffix
  function_name        = "${var.client_id}-${var.environment}-${local.function_name_suffix}"

  # Package
  s3_bucket = local.config.package.bucket
  s3_key    = local.config.package.key

  # Runtime
  handler = try(local.config.runtime.handler, "bootstrap")
  runtime = try(local.config.runtime.runtime, "provided.al2023")

  # Performance
  memory_size = try(local.config.performance.memory_mb, 256)
  timeout     = try(local.config.performance.timeout_seconds, 30)

  # Environment variables
  env_vars = try(local.config.environment, {})

  # Network
  enable_vpc = try(local.config.network.enabled, false)

  # IAM
  additional_policy_json = try(local.config.iam.additional_policy_json, "")
}

# ── Cross-workspace derived values ────────────────────────────────────────────
locals {
  kms_key_arn = nonsensitive(data.tfe_outputs.secure_baseline.values.kms_key_arn)
  vpc_id      = local.enable_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.vpc_id) : null
  subnet_ids  = local.enable_vpc ? nonsensitive(data.tfe_outputs.vpc[0].values.private_subnet_ids) : []
}
