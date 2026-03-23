# ── HCP Terraform ──────────────────────────────────────────────────────────────
variable "workspace_name" {
  description = "HCP Terraform workspace name this root runs in. Set as a workspace variable."
  type        = string
}

# ── Identity (set by control plane as workspace variables) ────────────────────
variable "client_id" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "terraform_role_arn" { type = string }
variable "external_id" {
  type      = string
  sensitive = true
}
variable "agency_principal_arn" { type = string }

# ── account-bootstrap options ─────────────────────────────────────────────────
variable "use_admin_policy" {
  description = "Use AdministratorAccess on TerraformDeployRole. False for prod."
  type        = bool
  default     = false
}

# ── secure-baseline feature flags ─────────────────────────────────────────────
variable "enable_cloudtrail" {
  type    = bool
  default = true
}
variable "enable_config" {
  type    = bool
  default = true
}
variable "enable_guardduty" {
  type    = bool
  default = true
}
variable "enable_security_hub" {
  type    = bool
  default = true
}
variable "enable_access_analyzer" {
  type    = bool
  default = true
}
variable "enable_notifications" {
  type    = bool
  default = true
}

variable "security_alert_emails" {
  type    = list(string)
  default = []
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "tags" {
  type    = map(string)
  default = {}
}
