resource "aws_api_gateway_resource" "this" {
  for_each = var.routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_method" "this" {
  for_each = local.route_methods

  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.this[each.value.route_key].id
  http_method   = each.value.method
  authorization = each.value.authorizer_key != null ? "CUSTOM" : "NONE"
  authorizer_id = each.value.authorizer_key != null ? aws_api_gateway_authorizer.this[each.value.authorizer_key].id : null
}

resource "aws_api_gateway_integration" "this" {
  for_each = local.route_methods

  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.this[each.value.route_key].id
  http_method             = aws_api_gateway_method.this[each.key].http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.integrations[each.value.integration_key].lambda_invoke_arn
}

# ── Child {proxy+} resources ─────────────────────────────────────────────────
# When proxy_child = true on a route, creates /{path_part}/{proxy+} under the
# named resource so sub-paths also route to the same integration.
# e.g. auth_proxy (path_part="auth") → /auth and /auth/{proxy+} both hit auth-handler.

resource "aws_api_gateway_resource" "child_proxy" {
  for_each = local.proxy_child_routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.this[each.key].id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "child_proxy" {
  for_each = local.child_proxy_methods

  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.child_proxy[each.value.route_key].id
  http_method   = each.value.method
  authorization = each.value.authorizer_key != null ? "CUSTOM" : "NONE"
  authorizer_id = each.value.authorizer_key != null ? aws_api_gateway_authorizer.this[each.value.authorizer_key].id : null
}

resource "aws_api_gateway_integration" "child_proxy" {
  for_each = local.child_proxy_methods

  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.child_proxy[each.value.route_key].id
  http_method             = aws_api_gateway_method.child_proxy[each.key].http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.integrations[each.value.integration_key].lambda_invoke_arn
}
