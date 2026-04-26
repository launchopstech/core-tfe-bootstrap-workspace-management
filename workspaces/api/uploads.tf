# ── Uploads Bucket (set "uploads.enabled": true to create) ──────────────────
module "uploads_bucket" {
  source = "../../modules/aws/s3-secure"
  count  = local.uploads_enabled ? 1 : 0

  client_id   = var.client_id
  environment = var.environment
  bucket_name = "${local.name_prefix}-api-uploads${local.name_suffix}"
  kms_key_arn = local.kms_key_arn
  tags        = var.tags
}
