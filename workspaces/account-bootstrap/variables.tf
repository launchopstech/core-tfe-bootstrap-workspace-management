# ── HCP Terraform ─────────────────────────────────────────────────────────────
variable "workspace_name" {
  description = "HCP Terraform workspace name this root runs in. Set as a workspace variable."
  type        = string
}

# ── Identity (set by control plane as workspace variables) ────────────────────
variable "client_id" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
