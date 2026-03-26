variable "client_id" { type = string }
variable "environment" { type = string }

variable "engine_version" {
  description = "Database engine version. Defaults to the PostgreSQL 16 major version so AWS can choose a currently supported minor release."
  type        = string
  default     = "16"
}

variable "parameter_group_family" {
  type    = string
  default = "aurora-postgresql16"
}

variable "instance_class" {
  description = "Instance class for cluster instances. Use 'db.serverless' for Serverless v2."
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of cluster instances (writer + readers)."
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

variable "backup_retention_days" {
  description = "Days to retain automated backups. Enforced minimum is 7."
  type        = number
  default     = 14
}

variable "deletion_protection" {
  description = "Enable deletion protection. Disable for dev/test environments."
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights. Disable to save cost in dev."
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable Enhanced Monitoring (60s interval). Disable to save cost in dev."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of the platform KMS key for storage and Performance Insights encryption."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "database_subnet_group_name" {
  type = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets — allowed to connect to the database."
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
