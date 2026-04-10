module "lambda" {
  source = "../../modules/aws/lambda-function"

  function_name                 = local.function_name
  client_id                     = var.client_id
  environment                   = var.environment
  description                   = "Standalone Lambda for ${var.client_id} ${var.environment} (${local.function_name_suffix})."
  s3_bucket                     = local.create_package_bucket ? module.code_bucket[0].bucket_id : local.resolved_s3_bucket
  s3_key                        = local.resolved_s3_key
  handler                       = local.handler
  runtime                       = local.runtime
  memory_size                   = local.memory_size
  timeout                       = local.timeout
  environment_variables         = local.env_vars
  vpc_id                        = local.vpc_id
  subnet_ids                    = local.subnet_ids
  kms_key_arn                   = local.kms_key_arn
  attach_additional_policy_json = length(local.merged_additional_policy_documents) > 0
  additional_policy_json        = length(local.merged_additional_policy_documents) > 0 ? data.aws_iam_policy_document.lambda_additional[0].json : ""
  tags                          = var.tags

  depends_on = [aws_s3_object.seed_package]
}
