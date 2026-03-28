locals {
  has_vpc = var.vpc_id != null && length(var.subnet_ids) > 0
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}
