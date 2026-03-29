data "archive_file" "seed_package" {
  count = local.upload_seed_package ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/../seed_code/seed_handler.py"
  output_path = "/tmp/${var.client_id}-${var.environment}-${local.function_name_suffix}-${replace(local.resolved_s3_key, "/", "-")}.zip"
}

resource "aws_s3_object" "seed_package" {
  count = local.upload_seed_package ? 1 : 0

  bucket       = local.create_package_bucket ? module.code_bucket[0].bucket_id : local.resolved_s3_bucket
  key          = local.resolved_s3_key
  source       = data.archive_file.seed_package[0].output_path
  content_type = "application/zip"
}
