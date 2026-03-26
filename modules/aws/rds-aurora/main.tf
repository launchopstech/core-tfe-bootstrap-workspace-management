terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  is_serverless = var.serverless_min_capacity != null
}

module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0" # v10.x requires AWS provider >= 6.18 and Terraform >= 1.11

  name            = "${var.client_id}-${var.environment}-aurora"
  engine          = "aurora-postgresql"
  engine_version  = var.engine_version
  master_username = var.db_username
  database_name   = var.db_name
  port            = var.port

  manage_master_user_password = true
  storage_encrypted           = true
  kms_key_id                  = var.kms_key_arn

  vpc_id               = var.vpc_id
  db_subnet_group_name = var.database_subnet_group_name

  # Security group — managed by the module
  create_security_group = true
  security_group_rules = {
    ingress_private = {
      type        = "ingress"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = var.private_subnet_cidrs
      description = "Database port from private subnets"
    }
  }

  deletion_protection   = var.deletion_protection
  publicly_accessible   = false
  copy_tags_to_snapshot = true
  backup_retention_period = max(var.backup_retention_days, 7)

  # Monitoring
  monitoring_interval    = var.enable_enhanced_monitoring ? 60 : 0
  create_monitoring_role = var.enable_enhanced_monitoring

  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? 7 : null
  performance_insights_kms_key_id       = var.enable_performance_insights ? var.kms_key_arn : null

  # Serverless v2 scaling (when configured)
  serverlessv2_scaling_configuration = local.is_serverless ? {
    min_capacity = var.serverless_min_capacity
    max_capacity = var.serverless_max_capacity
  } : {}

  # Cluster instances
  instances = { for i in range(var.instance_count) : "instance-${i}" => {
    instance_class = local.is_serverless ? "db.serverless" : var.instance_class
  } }

  apply_immediately = var.environment != "prod"

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}
