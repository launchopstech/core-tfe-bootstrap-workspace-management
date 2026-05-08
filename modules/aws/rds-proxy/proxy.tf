module "rds_proxy" {
  source  = "terraform-aws-modules/rds-proxy/aws"
  version = "~> 3.0"

  name          = local.proxy_name
  engine_family = var.engine_family
  debug_logging = var.environment != "prod"
  require_tls   = true

  idle_client_timeout     = var.idle_client_timeout
  max_connections_percent = var.max_connections_percent

  # VPC / networking — SG managed by our wrapper
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.proxy.id]

  # Auth — Secrets Manager + IAM
  # The community module auto-grants GetSecretValue on every ARN in this map.
  auth = merge(
    {
      "master" = {
        auth_scheme = "SECRETS"
        iam_auth    = "REQUIRED"
        secret_arn  = var.db_secret_arn
      }
    },
    {
      for idx, arn in var.additional_auth_secret_arns :
      "user-${idx}" => {
        auth_scheme = "SECRETS"
        iam_auth    = "REQUIRED"
        secret_arn  = arn
      }
    }
  )

  # IAM role — let community module create it
  create_iam_role = true
  iam_role_name   = "${local.proxy_name}-role"
  kms_key_arns    = [var.kms_key_arn]

  # Targets — instance or cluster
  target_db_instance     = !var.is_cluster
  db_instance_identifier = !var.is_cluster ? var.db_identifier : ""
  target_db_cluster      = var.is_cluster
  db_cluster_identifier  = var.is_cluster ? var.db_identifier : ""

  tags = local.base_tags
}
