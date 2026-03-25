variable "secure_baseline_workspace_name" {
  description = "Name of the secure-baseline workspace for this account. Used to read shared outputs."
  type        = string
}
variable "hcp_terraform_organization" {
  description = "HCP Terraform organization that owns sibling service workspaces."
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

# ── Identity (set by control plane) ──────────────────────────────────────────
variable "client_id" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

# ── VPC config ────────────────────────────────────────────────────────────────
variable "cidr_block" { type = string }
variable "azs" { type = list(string) }
variable "private_subnets" { type = list(string) }
variable "public_subnets" { type = list(string) }
variable "database_subnets" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
