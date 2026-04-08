resource "aws_s3_object" "seed_package" {
  count = local.upload_seed_package ? 1 : 0

  bucket                 = local.create_package_bucket ? module.code_bucket[0].bucket_id : local.resolved_s3_bucket
  key                    = local.resolved_s3_key
  source                 = "${path.module}/../seed_code/seed_handler.zip"
  content_type           = "application/zip"
  server_side_encryption = "aws:kms"
  kms_key_id             = local.kms_key_arn
  metadata = {
    seed_zip_hash = filemd5("${path.module}/../seed_code/seed_handler.zip")
  }

  lifecycle {
    ignore_changes = [key]
  }
}
