terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "core-aws"
    workspaces {
      name = var.workspace_name
    }
  }

  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn    = var.terraform_role_arn
    external_id = var.external_id
  }

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      ClientId    = var.client_id
      Environment = var.environment
    }
  }
}

module "account_bootstrap" {
  source = "../../modules/aws/account-bootstrap"

  client_id            = var.client_id
  environment          = var.environment
  agency_principal_arn = var.agency_principal_arn
  external_id          = var.external_id
  use_admin_policy     = var.use_admin_policy
  tags                 = var.tags
}

module "secure_baseline" {
  source = "../../modules/aws/secure-baseline"

  client_id             = var.client_id
  environment           = var.environment
  kms_key_arn           = module.account_bootstrap.kms_key_arn
  enable_cloudtrail     = var.enable_cloudtrail
  enable_config         = var.enable_config
  enable_guardduty      = var.enable_guardduty
  enable_security_hub   = var.enable_security_hub
  enable_access_analyzer = var.enable_access_analyzer
  enable_notifications  = var.enable_notifications
  security_alert_emails = var.security_alert_emails
  log_retention_days    = var.log_retention_days
  tags                  = var.tags
}
