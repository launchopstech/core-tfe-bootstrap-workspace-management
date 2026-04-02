resource "aws_wafv2_web_acl_association" "api_stage" {
  count = local.waf_enabled ? 1 : 0

  resource_arn = module.api_gateway[0].stage_arn
  web_acl_arn  = local.waf_web_acl_arn

  depends_on = [module.api_gateway]
}
