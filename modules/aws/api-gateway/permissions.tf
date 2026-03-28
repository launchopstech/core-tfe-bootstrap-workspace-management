resource "aws_lambda_permission" "this" {
  for_each = local.all_permissions

  statement_id  = "AllowAPIGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = each.value.source_arn
}
