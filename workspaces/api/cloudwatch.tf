resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  count = local.gateway_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-api-5xx${local.name_suffix}"
  alarm_description   = "API Gateway 5XX error rate for ${local.name_prefix}${local.name_suffix}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = "${local.name_prefix}-api${local.name_suffix}"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambdas

  alarm_name          = "${local.name_prefix}-${try(each.value.name, each.value.function_name_suffix)}${local.name_suffix}-errors"
  alarm_description   = "Lambda error rate for ${local.name_prefix}-${try(each.value.name, each.value.function_name_suffix)}${local.name_suffix}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.lambdas[each.key].function_name
  }

  tags = var.tags
}
