# ── HCP Terraform ──────────────────────────────────────────────────────────────
variable "workspace_name" {
  description = "HCP Terraform workspace name this root runs in. Set as a workspace variable."
  type        = string
}

# ── Identity (set by control plane as workspace variables) ────────────────────
variable "client_id" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

# ── Bootstrap inputs (set manually after CFN bootstrap) ───────────────────────
variable "kms_key_arn" {
  description = "ARN of the platform KMS key created by the CFN bootstrap. Output of cfn-terraform-bootstrap.yaml."
  type        = string
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
