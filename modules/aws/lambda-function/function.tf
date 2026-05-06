module "lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = var.function_name
  description   = var.description
  handler       = var.handler
  runtime       = var.runtime
  memory_size   = var.memory_size
  timeout       = var.timeout

  # Deployment package from S3
  create_package = false
  s3_existing_package = {
    bucket     = var.s3_bucket
    key        = var.s3_key
    version_id = var.s3_object_version
  }

  # Environment variables
  environment_variables = var.environment_variables

  # VPC
  vpc_subnet_ids         = local.has_vpc ? var.subnet_ids : null
  vpc_security_group_ids = local.has_vpc ? [aws_security_group.lambda[0].id] : null
  attach_network_policy  = local.has_vpc

  # CloudWatch logs
  cloudwatch_logs_retention_in_days = var.log_retention_days
  cloudwatch_logs_kms_key_id        = var.kms_key_arn

  # IAM — attach additional inline policy if provided
  attach_policy_json = var.attach_additional_policy_json
  policy_json        = var.additional_policy_json

  tags = local.base_tags
}
