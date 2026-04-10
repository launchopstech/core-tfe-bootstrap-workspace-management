data "aws_iam_policy_document" "lambda_secrets" {
  count = local.has_secret_refs ? 1 : 0

  statement {
    sid     = "SecretsManagerRead"
    actions = ["secretsmanager:GetSecretValue"]
    # try() mirrors the guard in locals.tf — keeps evaluation from hard-failing
    # on a missing key before the precondition message can surface.
    resources = compact([
      for secret_key in values(local.secret_refs) :
      try(local.secret_arns_by_key[secret_key], "")
    ])
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
    local.has_secret_refs ? [data.aws_iam_policy_document.lambda_secrets[0].json] : [],
  )
}

data "aws_iam_policy_document" "lambda_additional" {
  count = length(local.merged_additional_policy_documents) > 0 ? 1 : 0

  source_policy_documents = local.merged_additional_policy_documents
}
