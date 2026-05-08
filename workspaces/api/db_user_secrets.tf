# ── Per-user DB secrets for RDS Proxy backend auth ────────────────────────────
# RDS Proxy uses Secrets Manager password auth on the backend DB connection
# even when clients authenticate with IAM tokens. Each DB user that the proxy
# connects as needs its own secret in the proxy's auth config.

resource "random_password" "db_app_user" {
  count   = local.proxy_enabled ? 1 : 0
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "db_app_user" {
  count       = local.proxy_enabled ? 1 : 0
  name        = "${local.name_prefix}-db-app-user${local.name_suffix}"
  description = "RDS credentials for '${local.db_iam_username}' — used by RDS Proxy backend auth"
  kms_key_id  = local.kms_key_arn
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "db_app_user" {
  count     = local.proxy_enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.db_app_user[0].id
  secret_string = jsonencode({
    username = local.db_iam_username
    password = random_password.db_app_user[0].result
    engine   = "postgres"
    host     = local.db_instance_endpoint
    port     = 5432
    dbname   = local.db_name
  })
}
