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

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      ClientId    = var.client_id
      Environment = var.environment
    }
  }
}

# Pull shared outputs from the secure-baseline workspace
data "tfe_outputs" "secure_baseline" {
  organization = var.hcp_terraform_organization
  workspace    = var.secure_baseline_workspace_name
}

module "vpc" {
  source = "../../modules/aws/vpc"

  client_id        = var.client_id
  environment      = var.environment
  cidr_block       = var.cidr_block
  azs              = var.azs
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets
  logs_bucket_arn  = try(nonsensitive(data.tfe_outputs.secure_baseline.values.logs_bucket_arn), null)
  tags             = var.tags
}
