# ── Infrastructure inputs ────────────────────────────────────────────────────
variable "kms_key_arn" {
  description = "ARN of the platform KMS key from secure-baseline. Injected by the control plane."
  type        = string
}
variable "vpc_workspace_name" {
  description = "Name of the VPC workspace in the same project. Used to read VPC outputs at runtime."
  type        = string
}
variable "ssm_config_json" {
  description = "Optional SSM bridge config for private operational access."
  type        = any
  default     = {}
}
variable "hcp_terraform_organization" {
  description = "HCP Terraform organization."
  type        = string
  default     = "core-aws"
}

# Injected by control plane — informational only
variable "aws_account_id" {
  type    = string
  default = null
}
variable "aws_account_name" {
  type    = string
  default = null
}
variable "security_tier" {
  type    = string
  default = null
}
variable "service_family" {
  type    = string
  default = null
}
variable "selected_services" {
  type    = string
  default = null
}


# ── Identity ──────────────────────────────────────────────────────────────────
variable "client_id" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

# ── RDS config ────────────────────────────────────────────────────────────────
variable "enable_cluster" {
  description = "Deploy Aurora PostgreSQL cluster instead of a single RDS instance. Recommended for production."
  type        = bool
  default     = false
}
variable "engine" {
  type    = string
  default = "postgres"
}
variable "engine_version" {
  description = "Database engine version. Defaults to the PostgreSQL 16 major version so AWS can choose a currently supported minor release."
  type        = string
  default     = "16"
}
variable "major_engine_version" {
  type    = string
  default = "16"
}
variable "parameter_group_family" {
  type    = string
  default = "postgres16"
}
variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "max_allocated_storage" {
  type    = number
  default = 100
}
variable "db_name" {
  type    = string
  default = "app"
}
variable "db_username" {
  type    = string
  default = "dbadmin"
}
variable "port" {
  type    = number
  default = 5432
}
variable "multi_az" {
  type    = bool
  default = false
}
variable "backup_retention_days" {
  type    = number
  default = 14
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "enable_performance_insights" {
  type    = bool
  default = true
}
variable "enable_enhanced_monitoring" {
  type    = bool
  default = true
}

# ── Aurora cluster config ────────────────────────────────────────────────────
variable "cluster_instance_count" {
  description = "Number of Aurora cluster instances (writer + readers)."
  type        = number
  default     = 2
}
variable "serverless_min_capacity" {
  description = "Aurora Serverless v2 minimum ACU. Set to null for provisioned instances."
  type        = number
  default     = null
}
variable "serverless_max_capacity" {
  description = "Aurora Serverless v2 maximum ACU. Set to null for provisioned instances."
  type        = number
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
