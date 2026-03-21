terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.client_id}-${var.environment}-db"

  engine               = var.engine
  engine_version       = var.engine_version
  family               = var.parameter_group_family
  major_engine_version = var.major_engine_version
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage

  # Secure defaults — not overridable by callers
  storage_encrypted                  = true
  kms_key_id                         = var.kms_key_arn
  manage_master_user_password        = true
  iam_database_authentication_enabled = true
  deletion_protection                = true
  publicly_accessible                = false
  copy_tags_to_snapshot              = true
  backup_retention_period            = max(var.backup_retention_days, 14)
  delete_automated_backups           = false

  multi_az = var.environment == "prod" ? true : var.multi_az

  db_name  = var.db_name
  username = var.db_username
  port     = var.port

  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Enhanced monitoring
  monitoring_interval    = 60
  monitoring_role_name   = "${var.client_id}-${var.environment}-rds-monitoring"
  create_monitoring_role = true

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = var.kms_key_arn

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.client_id}-${var.environment}-rds"
  description = "RDS security group for ${var.client_id} ${var.environment}. Allows inbound from private subnets only."
  vpc_id      = var.vpc_id

  ingress {
    description = "Database port from private subnets"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}
