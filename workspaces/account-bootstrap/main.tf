terraform {
  required_version = ">= 1.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Agency bootstrap/preflight root. In MVP this workspace can verify that HCP
# Terraform OIDC can reach the expected AWS account before downstream deployers
# like secure-baseline, vpc, and rds run. The check is opt-in so portal setup
# can proceed before AWS trust is ready.

# This provider is only consumed by the conditional aws_preflight module below.
# When preflight is disabled, Terraform does not need to initialize AWS auth.
provider "aws" {
  alias                       = "preflight"
  region                      = var.aws_region
  access_key                  = var.enable_aws_preflight ? null : "bootstrap-preflight-disabled"
  secret_key                  = var.enable_aws_preflight ? null : "bootstrap-preflight-disabled"
  skip_credentials_validation = var.enable_aws_preflight ? false : true
  skip_metadata_api_check     = var.enable_aws_preflight ? false : true
  skip_requesting_account_id  = var.enable_aws_preflight ? false : true
  skip_region_validation      = var.enable_aws_preflight ? false : true

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

module "aws_preflight" {
  count = var.enable_aws_preflight ? 1 : 0

  source = "./modules/aws-preflight"
  providers = {
    aws = aws.preflight
  }

  client_id      = var.client_id
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id
}
