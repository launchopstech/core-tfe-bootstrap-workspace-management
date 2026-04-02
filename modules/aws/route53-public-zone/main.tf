locals {
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}

resource "aws_route53_zone" "this" {
  name    = var.zone_name
  comment = var.comment
  tags    = local.base_tags
}
