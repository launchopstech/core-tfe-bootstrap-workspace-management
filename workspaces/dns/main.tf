locals {
  config = var.dns_config_json

  zone_name = trimspace(try(local.config.zone_name, ""))
  comment   = try(local.config.comment, null)
  records   = try(local.config.records, {})
}

resource "terraform_data" "dns_config_validation" {
  input = local.config

  lifecycle {
    precondition {
      condition     = local.zone_name != ""
      error_message = "dns_config_json.zone_name is required."
    }

    precondition {
      condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$", local.zone_name))
      error_message = "dns_config_json.zone_name must be a valid DNS hostname without a trailing dot, for example dev.example.com."
    }
  }
}

module "public_zone" {
  source = "../../modules/aws/route53-public-zone"

  client_id   = var.client_id
  environment = var.environment
  zone_name   = local.zone_name
  comment     = local.comment
  tags        = var.tags

  depends_on = [terraform_data.dns_config_validation]
}

# ── Optional extra DNS records (e.g. Vercel CNAMEs, external service aliases) ──
resource "aws_route53_record" "extra" {
  for_each = local.records

  zone_id = module.public_zone.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}
