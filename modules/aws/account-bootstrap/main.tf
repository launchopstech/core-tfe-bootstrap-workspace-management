terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

################################################################################
# TerraformDeployRole — cross-account IAM role for HCP Terraform execution
################################################################################

data "aws_iam_policy_document" "terraform_assume_role" {
  statement {
    sid     = "AllowAgencyPrincipalWithExternalId"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.agency_principal_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

resource "aws_iam_role" "terraform_deploy" {
  name                 = var.role_name
  description          = "Cross-account role assumed by the agency Terraform principal to deploy infrastructure in this account."
  assume_role_policy   = data.aws_iam_policy_document.terraform_assume_role.json
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600

  tags = merge(var.tags, {
    ManagedBy    = "terraform"
    RoleClass    = "automation"
    ClientId     = var.client_id
    Environment  = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "terraform_deploy_admin" {
  count      = var.use_admin_policy ? 1 : 0
  role       = aws_iam_role.terraform_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "terraform_deploy_least_privilege" {
  count = var.use_admin_policy ? 0 : 1
  name  = "TerraformDeployLeastPrivilege"
  role  = aws_iam_role.terraform_deploy.id

  policy = data.aws_iam_policy_document.terraform_deploy_least_privilege[0].json
}

data "aws_iam_policy_document" "terraform_deploy_least_privilege" {
  count = var.use_admin_policy ? 0 : 1

  # IAM — scoped to paths to prevent unbounded privilege escalation
  statement {
    sid    = "IAMScopedToPath"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:PassRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:GetInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::*:role/terraform/*",
      "arn:aws:iam::*:instance-profile/terraform/*",
    ]
  }

  # Core AWS services needed for platform stacks
  statement {
    sid    = "CoreServiceAccess"
    effect = "Allow"
    actions = [
      "ec2:*",
      "eks:*",
      "rds:*",
      "s3:*",
      "kms:*",
      "logs:*",
      "cloudtrail:*",
      "config:*",
      "guardduty:*",
      "securityhub:*",
      "access-analyzer:*",
      "sns:*",
      "ssm:*",
      "backup:*",
    ]
    resources = ["*"]
  }

  # Read-only account-level calls always needed by Terraform
  statement {
    sid    = "ReadOnlyAccountLevel"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
      "iam:GetAccountSummary",
      "iam:ListAccountAliases",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

################################################################################
# KMS — account-level encryption key for logs and platform secrets
################################################################################

resource "aws_kms_key" "platform" {
  description             = "Platform encryption key for ${var.client_id} ${var.environment} — managed by agency Terraform."
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_platform.json

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
    KeyClass    = "platform"
  })
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.client_id}-${var.environment}-platform"
  target_key_id = aws_kms_key.platform.key_id
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_platform" {
  # Root account always retains full key admin
  statement {
    sid    = "RootAccountFullAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # TerraformDeployRole can use the key for encryption operations
  statement {
    sid    = "TerraformDeployRoleKeyUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.terraform_deploy.arn]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
  }

  # Allow AWS services to use the key (CloudTrail, Config, etc.)
  statement {
    sid    = "AWSServicesKeyUsage"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "cloudtrail.amazonaws.com",
        "config.amazonaws.com",
        "logs.amazonaws.com",
      ]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
  }
}

################################################################################
# Break-glass — read-only agency support role (does not use ExternalId)
################################################################################

data "aws_iam_policy_document" "break_glass_assume_role" {
  statement {
    sid     = "AllowAgencyBreakGlass"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.agency_principal_arn]
    }
  }
}

resource "aws_iam_role" "break_glass" {
  count                = var.create_break_glass_role ? 1 : 0
  name                 = "${var.role_name}-ReadOnly"
  description          = "Agency read-only break-glass role for ${var.client_id} ${var.environment}. Does not require ExternalId."
  assume_role_policy   = data.aws_iam_policy_document.break_glass_assume_role.json
  max_session_duration = 3600

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    RoleClass   = "break-glass"
    ClientId    = var.client_id
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "break_glass_readonly" {
  count      = var.create_break_glass_role ? 1 : 0
  role       = aws_iam_role.break_glass[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
