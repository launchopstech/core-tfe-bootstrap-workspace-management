# ── HCP Terraform ──────────────────────────────────────────────────────────────
variable "workspace_name" { type = string }
variable "secure_baseline_workspace_name" {
  description = "Name of the secure-baseline workspace for this account. Used to read shared outputs."
  type        = string
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
