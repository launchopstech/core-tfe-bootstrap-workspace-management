data "aws_iam_policy_document" "lambda" {
  for_each = local.lambdas_with_policies

  # rds-db:connect using RDS Proxy resource ID (prx-...) and IAM username
  dynamic "statement" {
    for_each = try(each.value.needs_db, false) ? [1] : []
    content {
      sid       = "RDSDBConnect"
      actions   = ["rds-db:connect"]
      resources = ["arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${module.rds_proxy[0].proxy_resource_id}/${local.db_iam_username}"]
    }
  }

  dynamic "statement" {
    for_each = try(each.value.needs_db, false) || try(each.value.needs_uploads, false) || length(keys(local.lambda_secret_refs[each.key])) > 0 ? [1] : []
    content {
      sid       = "KMSDecrypt"
      actions   = try(each.value.needs_uploads, false) ? ["kms:Decrypt", "kms:GenerateDataKey"] : ["kms:Decrypt"]
      resources = [local.kms_key_arn]
    }
  }

  dynamic "statement" {
    for_each = length(keys(local.lambda_secret_env_vars[each.key])) > 0 ? [1] : []
    content {
      sid       = "SecretsManagerRead"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = values(local.lambda_secret_env_vars[each.key])
    }
  }

  dynamic "statement" {
    for_each = try(each.value.needs_uploads, false) ? [1] : []
    content {
      sid       = "S3ReadWrite"
      actions   = ["s3:PutObject", "s3:GetObject"]
      resources = ["${module.uploads_bucket[0].bucket_arn}/*"]
    }
  }
}
