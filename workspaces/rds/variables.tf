# ── HCP Terraform ──────────────────────────────────────────────────────────────
variable "workspace_name" { type = string }
variable "secure_baseline_workspace_name" { type = string }
variable "vpc_workspace_name" {
  description = "Name of the VPC workspace for this account. RDS pulls subnet and CIDR outputs from here."
  type        = string
}

# ── Identity ──────────────────────────────────────────────────────────────────
variable "client_id" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

# ── RDS config ────────────────────────────────────────────────────────────────
variable "engine" {
  type    = string
  default = "postgres"
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

variable "tags" {
  type    = map(string)
  default = {}
}
