locals {
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })

  custom_domains = {
    for key, domain in var.custom_domains : key => {
      domain_name    = trimspace(domain.domain_name)
      hosted_zone_id = upper(trimspace(domain.hosted_zone_id))
      base_path      = trimspace(try(domain.base_path, ""))
    }
  }

  # Flatten routes × methods into a map for for_each
  route_methods = merge([
    for rk, route in var.routes : {
      for method in route.methods :
      "${rk}-${method}" => {
        route_key       = rk
        method          = method
        integration_key = route.integration_key
        authorizer_key  = route.authorizer_key
      }
    }
  ]...)

  # CORS origin — validated to be exactly one origin
  cors_origin = var.cors.allowed_origins[0]

  custom_domain_urls = {
    for key, domain in local.custom_domains :
    key => domain.base_path != "" ? "https://${domain.domain_name}/${domain.base_path}" : "https://${domain.domain_name}"
  }

  # Integration lambdas — permission for API to invoke via any method/path
  integration_permissions = {
    for k, v in var.integrations :
    k => {
      function_name = v.lambda_function_name
      source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
    }
  }

  # Authorizer lambdas — permission for API to invoke via authorizer path
  authorizer_permissions = {
    for k, v in var.authorizers :
    "auth-${k}" => {
      function_name = v.lambda_function_name
      source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/authorizers/*"
    }
  }

  all_permissions = merge(local.integration_permissions, local.authorizer_permissions)
}
