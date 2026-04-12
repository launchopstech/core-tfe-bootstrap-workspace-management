resource "aws_api_gateway_authorizer" "this" {
  for_each = var.authorizers

  name                   = "${var.api_name}-${each.key}"
  rest_api_id            = aws_api_gateway_rest_api.this.id
  type                   = "REQUEST"
  authorizer_uri         = each.value.lambda_invoke_arn
  authorizer_credentials = aws_iam_role.authorizer[each.key].arn

  authorizer_result_ttl_in_seconds = each.value.result_ttl_seconds
}

data "aws_iam_policy_document" "authorizer_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "authorizer" {
  for_each = var.authorizers

  name               = "${var.api_name}-${each.key}-invocation"
  assume_role_policy = data.aws_iam_policy_document.authorizer_assume.json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "authorizer_invoke" {
  for_each = var.authorizers

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [each.value.lambda_function_arn]
  }
}

resource "aws_iam_role_policy" "authorizer" {
  for_each = var.authorizers

  name   = "invoke-authorizer"
  role   = aws_iam_role.authorizer[each.key].id
  policy = data.aws_iam_policy_document.authorizer_invoke[each.key].json
}
