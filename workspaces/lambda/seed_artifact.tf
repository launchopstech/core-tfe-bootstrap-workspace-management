resource "terraform_data" "seed_package_generation" {
  count = local.upload_seed_package ? 1 : 0

  # Changes to the seed source should force the archive to be re-read during
  # apply on the same remote worker that uploads the S3 object.
  input = filesha256("${path.module}/../seed_code/seed_handler.py")
}

data "archive_file" "seed_package" {
  count = local.upload_seed_package ? 1 : 0
  depends_on = [
    terraform_data.seed_package_generation,
  ]

  type        = "zip"
  source_file = "${path.module}/../seed_code/seed_handler.py"
  output_path = "/tmp/${var.client_id}-${var.environment}-${local.function_name_suffix}-${replace(local.resolved_s3_key, "/", "-")}.zip"
}

resource "aws_s3_object" "seed_package" {
  count = local.upload_seed_package ? 1 : 0

  bucket                 = local.create_package_bucket ? module.code_bucket[0].bucket_id : local.resolved_s3_bucket
  key                    = local.resolved_s3_key
  source                 = data.archive_file.seed_package[0].output_path
  content_type           = "application/zip"
  server_side_encryption = "aws:kms"
  kms_key_id             = local.kms_key_arn
}
