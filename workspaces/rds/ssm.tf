data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  ssm_cfg = try(var.ssm_config_json, {})

  ssm_enabled                  = try(local.ssm_cfg.enabled, false)
  ssm_instance_type            = trimspace(try(local.ssm_cfg.instance_type, "t4g.nano"))
  ssm_ami_id                   = trimspace(try(local.ssm_cfg.ami_id, ""))
  ssm_subnet_index             = try(tonumber(local.ssm_cfg.subnet_index), 0)
  ssm_local_port               = try(tonumber(local.ssm_cfg.local_port), 15432)
  ssm_create_operator_role     = try(local.ssm_cfg.create_operator_role, false)
  ssm_operator_principal_arns  = try(tolist(local.ssm_cfg.operator_principal_arns), [])
  ssm_allow_master_secret_read = try(local.ssm_cfg.allow_master_secret_read, true)
  ssm_operator_role_enabled    = local.ssm_enabled && local.ssm_create_operator_role

  current_account_id = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)
  current_partition  = data.aws_partition.current.partition
  dns_suffix         = data.aws_partition.current.dns_suffix

  rds_endpoint          = var.enable_cluster ? module.aurora[0].cluster_endpoint : module.rds[0].db_instance_endpoint
  rds_secret_arn        = var.enable_cluster ? module.aurora[0].cluster_master_user_secret_arn : module.rds[0].db_secret_arn
  rds_security_group_id = var.enable_cluster ? module.aurora[0].security_group_id : module.rds[0].security_group_id
}

resource "terraform_data" "ssm_config_validation" {
  input = local.ssm_cfg

  lifecycle {
    precondition {
      condition = (
        !local.ssm_enabled ||
        (local.ssm_subnet_index >= 0 && local.ssm_subnet_index < length(local.private_subnet_ids))
      )
      error_message = "ssm_config_json.subnet_index must refer to an existing private subnet index."
    }

    precondition {
      condition = (
        !local.ssm_operator_role_enabled ||
        length(local.ssm_operator_principal_arns) > 0
      )
      error_message = "ssm_config_json.operator_principal_arns must be non-empty when create_operator_role is true."
    }
  }
}

module "ssm_bridge" {
  source = "../../modules/aws/ssm-bridge"
  count  = local.ssm_enabled ? 1 : 0

  client_id             = var.client_id
  environment           = var.environment
  vpc_id                = local.vpc_id
  subnet_id             = local.private_subnet_ids[local.ssm_subnet_index]
  rds_security_group_id = local.rds_security_group_id
  rds_port              = var.port
  kms_key_arn           = var.kms_key_arn
  instance_type         = local.ssm_instance_type
  ami_id                = local.ssm_ami_id
  tags                  = var.tags

  depends_on = [terraform_data.ssm_config_validation]
}

data "aws_iam_policy_document" "ssm_operator_assume_role" {
  count = local.ssm_operator_role_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.ssm_operator_principal_arns
    }
  }
}

resource "aws_iam_role" "ssm_operator" {
  count = local.ssm_operator_role_enabled ? 1 : 0

  name               = "${var.client_id}-${var.environment}-ssm-operator"
  assume_role_policy = data.aws_iam_policy_document.ssm_operator_assume_role[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "ssm_operator" {
  count = local.ssm_operator_role_enabled ? 1 : 0

  statement {
    sid     = "StartBridgeSession"
    actions = ["ssm:StartSession"]
    resources = [
      "arn:${local.current_partition}:ec2:${var.aws_region}:${local.current_account_id}:instance/${module.ssm_bridge[0].instance_id}",
      "arn:${local.current_partition}:ssm:${var.aws_region}::document/AWS-StartPortForwardingSessionToRemoteHost",
    ]
  }

  statement {
    sid = "ManageOwnSessions"
    actions = [
      "ssm:ResumeSession",
      "ssm:TerminateSession",
    ]
    resources = ["arn:${local.current_partition}:ssm:${var.aws_region}:${local.current_account_id}:session/$${aws:userid}-*"]
  }

  statement {
    sid = "DescribeAccessTargets"
    actions = [
      "ec2:DescribeInstances",
      "rds:DescribeDBClusters",
      "rds:DescribeDBInstances",
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = local.ssm_allow_master_secret_read ? [1] : []
    content {
      sid       = "ReadRdsMasterSecret"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [local.rds_secret_arn]
    }
  }

  dynamic "statement" {
    for_each = local.ssm_allow_master_secret_read ? [1] : []
    content {
      sid       = "DecryptRdsMasterSecret"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${var.aws_region}.${local.dns_suffix}"]
      }
    }
  }
}

resource "aws_iam_role_policy" "ssm_operator" {
  count = local.ssm_operator_role_enabled ? 1 : 0

  name   = "ssm-bridge-access"
  role   = aws_iam_role.ssm_operator[0].id
  policy = data.aws_iam_policy_document.ssm_operator[0].json
}
