data "aws_iam_policy_document" "secrets" {
  count = local.has_resolved_secret_refs ? 1 : 0

  statement {
    sid       = "SecretsManagerRead"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(local.secret_env_vars)
  }

  statement {
    sid       = "KMSDecrypt"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arn]
  }
}

locals {
  merged_additional_policy_documents = concat(
    trimspace(local.additional_policy_json) != "" ? [local.additional_policy_json] : [],
    local.has_resolved_secret_refs ? [data.aws_iam_policy_document.secrets[0].json] : [],
  )
}

data "aws_iam_policy_document" "lambda_additional" {
  count = length(local.merged_additional_policy_documents) > 0 ? 1 : 0

  source_policy_documents = local.merged_additional_policy_documents
}
