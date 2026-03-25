terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.client_id}-${var.environment}"
  cidr = var.cidr_block

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  database_subnets = var.database_subnets

  # NAT Gateway — single for non-prod, one-per-AZ for prod
  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  one_nat_gateway_per_az = var.environment == "prod"

  # DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Flow logs — enabled only after secure-baseline has been applied and
  # its logs_bucket_arn output is available.
  enable_flow_log                      = var.logs_bucket_arn != null
  flow_log_destination_type            = "s3"
  flow_log_destination_arn             = var.logs_bucket_arn
  flow_log_file_format                 = "parquet"
  flow_log_traffic_type                = "ALL"
  create_flow_log_cloudwatch_log_group = false
  create_flow_log_cloudwatch_iam_role  = false

  # Subnet tagging for EKS discovery
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}
