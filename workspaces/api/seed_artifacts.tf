locals {
  seed_artifact_source_files = local.upload_seed_artifacts ? {
    for lambda_key, lambda_cfg in local.lambdas :
    lambda_key => (contains(keys(local.authorizer_lambda_keys), lambda_key) ? "${path.module}/../seed_code/seed_authorizer.py" : "${path.module}/../seed_code/seed_handler.py")
  } : {}
}

resource "terraform_data" "seed_artifact_generation" {
  for_each = local.seed_artifact_source_files

  # Changes to the underlying source file should force the archive to be
  # re-read during apply on the same remote worker that uploads the S3 object.
  input = filesha256(each.value)
}

data "archive_file" "seed_artifacts" {
  for_each = local.seed_artifact_source_files
  depends_on = [
    terraform_data.seed_artifact_generation,
  ]

  type        = "zip"
  source_file = each.value
  output_path = "/tmp/${var.client_id}-${var.environment}-api-${each.key}-${local.resolved_artifacts_version}.zip"
}

resource "aws_s3_object" "seed_artifacts" {
  for_each = data.archive_file.seed_artifacts

  bucket       = local.create_artifacts_bucket ? module.code_bucket[0].bucket_id : local.resolved_artifacts_bucket
  key          = "${local.resolved_artifacts_key_prefix}/${each.key}-${local.resolved_artifacts_version}.zip"
  source       = each.value.output_path
  content_type = "application/zip"
}
