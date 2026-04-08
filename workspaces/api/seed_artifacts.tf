locals {
  seed_artifact_source_files = local.upload_seed_artifacts ? {
    for lambda_key, lambda_cfg in local.lambdas :
    lambda_key => {
      key = "${local.resolved_artifacts_key_prefix}/${lambda_key}-${local.resolved_artifacts_version}.zip"
      source = (
        contains(keys(local.authorizer_lambda_keys), lambda_key)
        ? "${path.module}/../seed_code/seed_authorizer.zip"
        : "${path.module}/../seed_code/seed_handler.zip"
      )
    }
  } : {}
}

resource "aws_s3_object" "seed_artifacts" {
  for_each = local.seed_artifact_source_files

  bucket                 = local.create_artifacts_bucket ? module.code_bucket[0].bucket_id : local.resolved_artifacts_bucket
  key                    = each.value.key
  source                 = each.value.source
  content_type           = "application/zip"
  server_side_encryption = "aws:kms"
  kms_key_id             = local.kms_key_arn
  metadata = {
    seed_zip_hash = filemd5(each.value.source)
  }
}
