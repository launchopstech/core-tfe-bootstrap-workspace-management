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
  attach_additional_policy_json = trimspace(local.additional_policy_json) != ""
  additional_policy_json        = local.additional_policy_json
  tags                          = var.tags
}
