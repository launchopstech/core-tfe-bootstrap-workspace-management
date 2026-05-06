data "tfe_outputs" "secure_baseline" {
  organization = var.hcp_terraform_organization
  workspace    = var.secure_baseline_workspace_name
}

data "tfe_outputs" "vpc" {
  count        = local.needs_vpc ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = var.vpc_workspace_name
}

data "tfe_outputs" "rds" {
  count        = local.needs_rds ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = var.rds_workspace_name
}

data "tfe_outputs" "dns" {
  count        = local.use_dns_workspace ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = local.normalized_dns_workspace_name
}

data "tfe_outputs" "waf" {
  count        = local.use_waf_workspace ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = local.normalized_waf_workspace_name
}

data "tfe_outputs" "secrets" {
  count        = local.use_secrets_workspace ? 1 : 0
  organization = var.hcp_terraform_organization
  workspace    = local.normalized_secrets_workspace_name
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Latest S3 key lookup for CI/CD-managed lambdas (upload_seed_code = false) ──
# forge-core uploads with SHA-based keys; this resolves the latest by LastModified.
data "external" "latest_lambda_key" {
  for_each = {
    for k, v in local.lambdas : k => v
    if !local.lambda_uses_seed_artifact[k]
  }

  program = ["bash", "${path.module}/scripts/latest_s3_key.sh"]

  query = {
    bucket   = local.resolved_artifacts_bucket
    prefix   = "${local.resolved_artifacts_key_prefix}/${each.key}-"
    fallback = "${local.resolved_artifacts_key_prefix}/${each.key}-${local.resolved_artifacts_version}.zip"
  }

  depends_on = [module.code_bucket]
}

data "aws_s3_object" "lambda_package" {
  for_each = {
    for k, v in local.lambdas : k => v
    if !local.lambda_uses_seed_artifact[k]
  }

  bucket = local.create_artifacts_bucket ? module.code_bucket[0].bucket_id : local.resolved_artifacts_bucket
  key    = data.external.latest_lambda_key[each.key].result.key

  depends_on = [module.code_bucket]
}
