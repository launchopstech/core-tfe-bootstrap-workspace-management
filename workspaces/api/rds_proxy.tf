# ── RDS Proxy (set "database.proxy_enabled": true to create) ─────────────────
module "rds_proxy" {
  source = "../../modules/aws/rds-proxy"
  count  = local.proxy_enabled ? 1 : 0

  client_id                   = var.client_id
  environment                 = var.environment
  db_identifier               = local.db_identifier
  is_cluster                  = local.is_cluster
  db_secret_arn               = local.db_secret_arn
  vpc_id                      = local.vpc_id
  subnet_ids                  = local.private_subnet_ids
  allowed_security_group_ids  = [for k in local.db_lambda_keys : module.lambdas[k].security_group_id]
  rds_security_group_id       = local.rds_sg_id
  kms_key_arn                 = local.kms_key_arn
  idle_client_timeout         = try(local.db_cfg.proxy_idle_timeout, 1800)
  max_connections_percent     = try(local.db_cfg.proxy_max_connections_percent, 100)
  additional_auth_secret_arns = local.proxy_enabled ? [aws_secretsmanager_secret.db_app_user[0].arn] : []
  tags                        = var.tags
}
