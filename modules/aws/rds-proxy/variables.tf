variable "client_id" {
  description = "Client identifier."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, qa, prod, workbench)."
  type        = string
}

variable "db_identifier" {
  description = "RDS instance identifier or Aurora cluster identifier."
  type        = string
}

variable "is_cluster" {
  description = "Whether the target is an Aurora cluster (true) or single instance (false)."
  type        = bool
  default     = false
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN for the database master user password."
  type        = string
}

variable "engine_family" {
  description = "Engine family for the proxy (MYSQL or POSTGRESQL)."
  type        = string
  default     = "POSTGRESQL"
}

variable "vpc_id" {
  description = "VPC ID where the proxy will be placed."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the proxy (should be the private subnets)."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to the proxy (e.g. Lambda SGs)."
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID of the RDS instance or cluster."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for Secrets Manager decryption."
  type        = string
}

variable "idle_client_timeout" {
  description = "Idle client connection timeout in seconds."
  type        = number
  default     = 1800
}

variable "max_connections_percent" {
  description = "Maximum percentage of available database connections the proxy can use."
  type        = number
  default     = 100
}

variable "port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
