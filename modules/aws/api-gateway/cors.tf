resource "aws_api_gateway_method" "options" {
  for_each = var.routes

  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.this[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  for_each = var.routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  for_each = var.routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_200" {
  for_each = var.routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options_200[each.key].status_code

  response_parameters = local.cors_response_parameters
}

# ── CORS headers on API Gateway error responses (authorizer 401/403, etc.) ──────

resource "aws_api_gateway_gateway_response" "cors_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "DEFAULT_4XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'${local.cors_origin}'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_5xx" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "DEFAULT_5XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'${local.cors_origin}'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_unauthorized" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "UNAUTHORIZED"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'${local.cors_origin}'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_access_denied" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "ACCESS_DENIED"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'${local.cors_origin}'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_authorizer_failure" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "AUTHORIZER_FAILURE"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'${local.cors_origin}'"
  }
}

# ── CORS OPTIONS for child {proxy+} resources ─────────────────────────────────

resource "aws_api_gateway_method" "child_proxy_options" {
  for_each = local.proxy_child_routes

  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.child_proxy[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "child_proxy_options" {
  for_each = local.proxy_child_routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.child_proxy[each.key].id
  http_method = aws_api_gateway_method.child_proxy_options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "child_proxy_options_200" {
  for_each = local.proxy_child_routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.child_proxy[each.key].id
  http_method = aws_api_gateway_method.child_proxy_options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "child_proxy_options_200" {
  for_each = local.proxy_child_routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.child_proxy[each.key].id
  http_method = aws_api_gateway_method.child_proxy_options[each.key].http_method
  status_code = aws_api_gateway_method_response.child_proxy_options_200[each.key].status_code

  response_parameters = local.cors_response_parameters
}
