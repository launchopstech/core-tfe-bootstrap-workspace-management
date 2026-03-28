resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.api_name}"
  retention_in_days = var.stage.log_retention_days
  tags              = local.base_tags
}
