locals {
  config = var.dns_config_json

  zone_name = trimspace(try(local.config.zone_name, ""))
  comment   = try(local.config.comment, null)
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
