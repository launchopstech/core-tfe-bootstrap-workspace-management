resource "aws_acm_certificate" "custom_domain" {
  for_each = local.custom_domains

  domain_name       = each.value.domain_name
  validation_method = "DNS"
  tags              = local.base_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "custom_domain_validation" {
  for_each = local.custom_domains

  zone_id         = each.value.hosted_zone_id
  allow_overwrite = true
  name            = one(aws_acm_certificate.custom_domain[each.key].domain_validation_options).resource_record_name
  records         = [one(aws_acm_certificate.custom_domain[each.key].domain_validation_options).resource_record_value]
  ttl             = 60
  type            = one(aws_acm_certificate.custom_domain[each.key].domain_validation_options).resource_record_type
}

resource "aws_acm_certificate_validation" "custom_domain" {
  for_each = local.custom_domains

  certificate_arn         = aws_acm_certificate.custom_domain[each.key].arn
  validation_record_fqdns = [aws_route53_record.custom_domain_validation[each.key].fqdn]
}

resource "aws_api_gateway_domain_name" "custom" {
  for_each = local.custom_domains

  domain_name              = each.value.domain_name
  regional_certificate_arn = aws_acm_certificate_validation.custom_domain[each.key].certificate_arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.base_tags
}

resource "aws_api_gateway_base_path_mapping" "custom" {
  for_each = local.custom_domains

  api_id      = aws_api_gateway_rest_api.this.id
  domain_name = aws_api_gateway_domain_name.custom[each.key].domain_name
  stage_name  = aws_api_gateway_stage.this.stage_name
  base_path   = each.value.base_path != "" ? each.value.base_path : null
}

resource "aws_route53_record" "custom_domain_alias" {
  for_each = local.custom_domains

  zone_id = each.value.hosted_zone_id
  name    = each.value.domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.custom[each.key].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.custom[each.key].regional_zone_id
    evaluate_target_health = false
  }
}
