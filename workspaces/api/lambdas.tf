# ── Lambda Functions (for_each — omit "lambdas" config section to skip) ──────
module "lambdas" {
  source   = "../../modules/aws/lambda-function"
  for_each = local.lambdas

  function_name = "${local.name_prefix}-${try(each.value.name, each.value.function_name_suffix)}${local.name_suffix}"
  client_id     = var.client_id
  environment   = var.environment
  description   = "API Lambda ${each.key} for ${var.client_id} ${var.environment}."
  s3_bucket = local.create_artifacts_bucket ? module.code_bucket[0].bucket_id : local.resolved_artifacts_bucket
  s3_key = try(local.lambdas[each.key].upload_seed_code, false) ? "${local.resolved_artifacts_key_prefix}/${each.key}-${local.resolved_artifacts_version}.zip" : data.external.latest_lambda_key[each.key].result.key
  handler       = try(each.value.handler, "bootstrap")
  runtime       = try(each.value.runtime, "provided.al2023")
  memory_size   = try(each.value.memory_mb, 256)
  timeout       = try(each.value.timeout_seconds, 30)
  kms_key_arn   = local.kms_key_arn
  tags          = var.tags

  # needs_db implies VPC attachment — DB Lambdas always need VPC for RDS Proxy access
  vpc_id     = try(each.value.needs_vpc, false) || try(each.value.needs_db, false) ? local.vpc_id : null
  subnet_ids = try(each.value.needs_vpc, false) || try(each.value.needs_db, false) ? local.private_subnet_ids : []

  environment_variables         = local.lambda_env_vars[each.key]
  attach_additional_policy_json = contains(keys(local.lambdas_with_policies), each.key)
  additional_policy_json        = try(data.aws_iam_policy_document.lambda[each.key].json, "")

  depends_on = [aws_s3_object.seed_artifacts]
}
