resource "aws_security_group" "proxy" {
  name        = "${local.proxy_name}-sg"
  description = "RDS Proxy security group for ${var.client_id} ${var.environment}."
  vpc_id      = var.vpc_id
  tags        = local.base_tags
}

resource "aws_security_group_rule" "proxy_ingress" {
  count = length(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id        = aws_security_group.proxy.id
  description              = "Allow inbound from Lambda"
}

resource "aws_security_group_rule" "proxy_egress_rds" {
  type                     = "egress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = var.rds_security_group_id
  security_group_id        = aws_security_group.proxy.id
  description              = "Allow outbound to RDS"
}
