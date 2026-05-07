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

# VPC outputs — read at runtime from the sibling VPC workspace in the same project.
data "tfe_outputs" "vpc" {
  organization = var.hcp_terraform_organization
  workspace    = var.vpc_workspace_name
}

locals {
  vpc_id                     = nonsensitive(data.tfe_outputs.vpc.values.vpc_id)
  database_subnet_group_name = nonsensitive(data.tfe_outputs.vpc.values.database_subnet_group_name)
  private_subnet_ids         = nonsensitive(data.tfe_outputs.vpc.values.private_subnet_ids)
  private_subnet_cidrs       = nonsensitive(data.tfe_outputs.vpc.values.private_subnet_cidrs)
}

# Preserve state address for workspaces deployed before enable_cluster was added.
moved {
  from = module.rds
  to   = module.rds[0]
}

# ── Single RDS Instance (default) ────────────────────────────────────────────
module "rds" {
  source = "../../modules/aws/rds-secure"
  count  = var.enable_cluster ? 0 : 1

  client_id                   = var.client_id
  environment                 = var.environment
  engine                      = var.engine
  engine_version              = var.engine_version
  major_engine_version        = var.major_engine_version
  parameter_group_family      = var.parameter_group_family
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = var.max_allocated_storage
  db_name                     = var.db_name
  db_username                 = var.db_username
  port                        = var.port
  multi_az                    = var.multi_az
  backup_retention_days       = var.backup_retention_days
  deletion_protection         = var.deletion_protection
  enable_performance_insights = var.enable_performance_insights
  enable_enhanced_monitoring  = var.enable_enhanced_monitoring
  kms_key_arn                 = var.kms_key_arn
  vpc_id                      = local.vpc_id
  database_subnet_group_name  = local.database_subnet_group_name
  private_subnet_cidrs        = local.private_subnet_cidrs
  tags                        = var.tags
}

# ── Aurora PostgreSQL Cluster (production) ───────────────────────────────────
module "aurora" {
  source = "../../modules/aws/rds-aurora"
  count  = var.enable_cluster ? 1 : 0

  client_id                   = var.client_id
  environment                 = var.environment
  engine_version              = var.engine_version
  parameter_group_family      = "aurora-postgresql16"
  instance_class              = var.instance_class
  instance_count              = var.cluster_instance_count
  serverless_min_capacity     = var.serverless_min_capacity
  serverless_max_capacity     = var.serverless_max_capacity
  db_name                     = var.db_name
  db_username                 = var.db_username
  port                        = var.port
  backup_retention_days       = var.backup_retention_days
  deletion_protection         = var.deletion_protection
  enable_performance_insights = var.enable_performance_insights
  enable_enhanced_monitoring  = var.enable_enhanced_monitoring
  kms_key_arn                 = var.kms_key_arn
  vpc_id                      = local.vpc_id
  database_subnet_group_name  = local.database_subnet_group_name
  private_subnet_cidrs        = local.private_subnet_cidrs
  tags                        = var.tags
}
