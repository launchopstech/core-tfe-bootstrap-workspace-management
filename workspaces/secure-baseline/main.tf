terraform {
  required_version = ">= 1.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Authentication via HCP Terraform Dynamic Provider Credentials (OIDC).
  # Set TFC_AWS_PROVIDER_AUTH=true and TFC_AWS_RUN_ROLE_ARN on the workspace.
  # No long-lived access keys required.

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      ClientId    = var.client_id
      Environment = var.environment
    }
  }
}

module "secure_baseline" {
  source = "../../modules/aws/secure-baseline"

  client_id              = var.client_id
  environment            = var.environment
  kms_key_arn            = var.kms_key_arn
  enable_cloudtrail      = var.enable_cloudtrail
  enable_config          = var.enable_config
  enable_guardduty       = var.enable_guardduty
  enable_security_hub    = var.enable_security_hub
  enable_access_analyzer = var.enable_access_analyzer
  enable_notifications   = var.enable_notifications
  security_alert_emails  = var.security_alert_emails
  log_retention_days     = var.log_retention_days
  tags                   = var.tags
}
