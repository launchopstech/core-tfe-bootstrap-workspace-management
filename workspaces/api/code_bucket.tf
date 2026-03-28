# ── Optional code bucket for externally-built Lambda artifacts ───────────────
module "code_bucket" {
  source = "../../modules/aws/s3-secure"
  count  = local.create_artifacts_bucket ? 1 : 0

  client_id               = var.client_id
  environment             = var.environment
  bucket_name             = local.default_artifacts_bucket_name
  kms_key_arn             = local.kms_key_arn
  force_destroy           = var.environment != "prod"
  lifecycle_rules_enabled = false
  tags                    = var.tags
}
