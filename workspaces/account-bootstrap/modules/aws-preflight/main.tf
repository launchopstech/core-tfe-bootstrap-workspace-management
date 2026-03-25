terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
