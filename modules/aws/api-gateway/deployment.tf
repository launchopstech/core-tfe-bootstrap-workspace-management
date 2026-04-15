resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode({
      rest_api = {
        name        = aws_api_gateway_rest_api.this.name
        description = aws_api_gateway_rest_api.this.description
      }
      resources = {
        for k, v in aws_api_gateway_resource.this : k => {
          parent_id = v.parent_id
          path_part = v.path_part
        }
      }
      child_resources = {
        for k, v in aws_api_gateway_resource.child_proxy : k => {
          parent_id = v.parent_id
          path_part = v.path_part
        }
      }
      methods = {
        for k, v in aws_api_gateway_method.this : k => {
          resource_id   = v.resource_id
          http_method   = v.http_method
          authorization = v.authorization
          authorizer_id = v.authorizer_id
        }
      }
      child_methods = {
        for k, v in aws_api_gateway_method.child_proxy : k => {
          resource_id   = v.resource_id
          http_method   = v.http_method
          authorization = v.authorization
          authorizer_id = v.authorizer_id
        }
      }
      options_methods = {
        for k, v in aws_api_gateway_method.options : k => {
          resource_id = v.resource_id
          http_method = v.http_method
        }
      }
      child_options_methods = {
        for k, v in aws_api_gateway_method.child_proxy_options : k => {
          resource_id = v.resource_id
          http_method = v.http_method
        }
      }
      integrations = {
        for k, v in aws_api_gateway_integration.this : k => {
          resource_id             = v.resource_id
          http_method             = v.http_method
          type                    = v.type
          integration_http_method = v.integration_http_method
          uri                     = v.uri
        }
      }
      child_integrations = {
        for k, v in aws_api_gateway_integration.child_proxy : k => {
          resource_id             = v.resource_id
          http_method             = v.http_method
          type                    = v.type
          integration_http_method = v.integration_http_method
          uri                     = v.uri
        }
      }
      options_integrations = {
        for k, v in aws_api_gateway_integration.options : k => {
          resource_id       = v.resource_id
          http_method       = v.http_method
          type              = v.type
          request_templates = v.request_templates
        }
      }
      child_options_integrations = {
        for k, v in aws_api_gateway_integration.child_proxy_options : k => {
          resource_id       = v.resource_id
          http_method       = v.http_method
          type              = v.type
          request_templates = v.request_templates
        }
      }
      authorizers = {
        for k, v in aws_api_gateway_authorizer.this : k => {
          name                             = v.name
          type                             = v.type
          authorizer_uri                   = v.authorizer_uri
          authorizer_credentials           = v.authorizer_credentials
          authorizer_result_ttl_in_seconds = v.authorizer_result_ttl_in_seconds
        }
      }
      gateway_responses = {
        cors_4xx = {
          response_type       = aws_api_gateway_gateway_response.cors_4xx.response_type
          response_parameters = aws_api_gateway_gateway_response.cors_4xx.response_parameters
        }
        cors_5xx = {
          response_type       = aws_api_gateway_gateway_response.cors_5xx.response_type
          response_parameters = aws_api_gateway_gateway_response.cors_5xx.response_parameters
        }
        cors_unauthorized = {
          response_type       = aws_api_gateway_gateway_response.cors_unauthorized.response_type
          response_parameters = aws_api_gateway_gateway_response.cors_unauthorized.response_parameters
        }
        cors_access_denied = {
          response_type       = aws_api_gateway_gateway_response.cors_access_denied.response_type
          response_parameters = aws_api_gateway_gateway_response.cors_access_denied.response_parameters
        }
        cors_authorizer_failure = {
          response_type       = aws_api_gateway_gateway_response.cors_authorizer_failure.response_type
          response_parameters = aws_api_gateway_gateway_response.cors_authorizer_failure.response_parameters
        }
      }
      cors = {
        config = var.cors
        method_responses = {
          for k, v in aws_api_gateway_method_response.options_200 : k => {
            status_code         = v.status_code
            response_parameters = v.response_parameters
          }
        }
        integration_responses = {
          for k, v in aws_api_gateway_integration_response.options_200 : k => {
            status_code         = v.status_code
            response_parameters = v.response_parameters
          }
        }
        child_method_responses = {
          for k, v in aws_api_gateway_method_response.child_proxy_options_200 : k => {
            status_code         = v.status_code
            response_parameters = v.response_parameters
          }
        }
        child_integration_responses = {
          for k, v in aws_api_gateway_integration_response.child_proxy_options_200 : k => {
            status_code         = v.status_code
            response_parameters = v.response_parameters
          }
        }
      }
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_authorizer.this,
    aws_api_gateway_method.this,
    aws_api_gateway_method.options,
    aws_api_gateway_method.child_proxy,
    aws_api_gateway_method.child_proxy_options,
    aws_api_gateway_integration.this,
    aws_api_gateway_integration.options,
    aws_api_gateway_integration.child_proxy,
    aws_api_gateway_integration.child_proxy_options,
    aws_api_gateway_method_response.options_200,
    aws_api_gateway_method_response.child_proxy_options_200,
    aws_api_gateway_integration_response.options_200,
    aws_api_gateway_integration_response.child_proxy_options_200,
    aws_api_gateway_gateway_response.cors_4xx,
    aws_api_gateway_gateway_response.cors_5xx,
    aws_api_gateway_gateway_response.cors_unauthorized,
    aws_api_gateway_gateway_response.cors_access_denied,
    aws_api_gateway_gateway_response.cors_authorizer_failure,
  ]
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage.name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.base_tags
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    data_trace_enabled = var.environment != "prod"
    metrics_enabled    = true
  }
}
