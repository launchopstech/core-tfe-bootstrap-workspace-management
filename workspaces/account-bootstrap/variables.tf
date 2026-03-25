# ── Identity (set by control plane as workspace variables) ────────────────────
variable "client_id" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "aws_account_id" {
  description = "Expected AWS account ID for this workspace. Used to verify OIDC is targeting the right account."
  type        = string
}

# Injected by control plane — informational only
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
