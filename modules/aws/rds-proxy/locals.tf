locals {
  proxy_name = "${var.client_id}-${var.environment}-rds-proxy"
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}
