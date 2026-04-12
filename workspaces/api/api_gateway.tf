# ── API Gateway (set "gateway.enabled": true or include "gateway" section) ───
module "api_gateway" {
  source = "../../modules/aws/api-gateway"
  count  = local.gateway_enabled ? 1 : 0

  client_id   = var.client_id
  environment = var.environment
  api_name    = "${local.name_prefix}-api"

  authorizers = {
    for ak, av in try(local.gw.authorizers, {}) : ak => {
      lambda_invoke_arn    = module.lambdas[av.lambda_key].invoke_arn
      lambda_function_arn  = module.lambdas[av.lambda_key].function_arn
      lambda_function_name = module.lambdas[av.lambda_key].function_name
    }
  }

  integrations = {
    for ik in distinct([for rk, rv in local.gw.routes : rv.integration_key]) : ik => {
      lambda_invoke_arn    = module.lambdas[ik].invoke_arn
      lambda_function_name = module.lambdas[ik].function_name
    }
  }

  routes = {
    for rk, rv in local.gw.routes : rk => {
      path_part       = rv.path_part
      methods         = rv.methods
      integration_key = rv.integration_key
      authorizer_key  = try(rv.authorizer_key, null)
      proxy_child     = try(rv.proxy_child, false)
    }
  }

  cors = try(local.gw.cors, { allowed_origins = ["*"] })

  stage = try(local.gw.stage, {})

  custom_domains = local.resolved_custom_domains

  tags = var.tags
}
