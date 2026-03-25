terraform {
  required_version = ">= 1.2"
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
  # TFC_AWS_PROVIDER_AUTH and TFC_AWS_RUN_ROLE_ARN are set by the control plane.

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      ClientId    = var.client_id
      Environment = var.environment
    }
  }
}

# Verifies OIDC auth is working and the correct account is targeted.
data "aws_caller_identity" "current" {
  lifecycle {
    postcondition {
      condition     = self.account_id == var.aws_account_id
      error_message = "OIDC resolved AWS account '${self.account_id}', but this workspace is configured for '${var.aws_account_id}'."
    }
  }
}
data "aws_region" "current" {}
