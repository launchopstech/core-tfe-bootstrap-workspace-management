variable "client_id" { type = string }
variable "environment" { type = string }

variable "engine" {
  description = "Database engine (postgres, mysql, mariadb)."
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  type    = string
  default = "16.4"
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
  description = "Maximum storage for autoscaling. Set to 0 to disable autoscaling."
  type        = number
  default     = 100
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
  description = "Force multi-AZ. Always true in prod regardless of this value."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days to retain automated backups. Enforced minimum is 14."
  type        = number
  default     = 14
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
