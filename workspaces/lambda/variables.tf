# ── Identity (injected by account portal) ─────────────────────────────────────
variable "client_id" {
  description = "Client identifier."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, qa, prod, workbench)."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

# ── Informational (injected by account portal, not required for function) ─────
variable "aws_account_id" {
  description = "AWS account ID."
  type        = string
  default     = null
}

variable "aws_account_name" {
  description = "AWS account name."
  type        = string
  default     = null
}

variable "security_tier" {
  description = "Security tier (standard or high)."
  type        = string
  default     = null
}

variable "service_family" {
  description = "Service family."
  type        = string
  default     = null
}

variable "selected_services" {
  description = "JSON-encoded list of enabled services."
  type        = string
  default     = null
}

# ── Organization ──────────────────────────────────────────────────────────────
variable "hcp_terraform_organization" {
  description = "HCP Terraform organization name."
  type        = string
  default     = "core-aws"
}

# ── Dependency workspace names (injected by account portal) ───────────────────
variable "secure_baseline_workspace_name" {
  description = "Name of the secure-baseline workspace (for KMS key ARN)."
  type        = string
}

variable "vpc_workspace_name" {
  description = "Name of the VPC workspace. Required only when network.enabled is true."
  type        = string
  default     = ""
}

# ── Lambda configuration (JSON blob) ──────────────────────────────────────────
variable "lambda_config_json" {
  description = <<-EOT
    JSON-encoded Lambda configuration. Expected shape:
    {
      "function_name_suffix": "my-worker",
      "package":     { "bucket": "artifacts", "key": "worker-v1.zip" },
      "runtime":     { "handler": "bootstrap", "runtime": "provided.al2023" },
      "performance": { "memory_mb": 256, "timeout_seconds": 30 },
      "environment": { "KEY": "value" },
      "network":     { "enabled": false },
      "logging":     { "retention_days": 90 },
      "iam":         { "additional_policy_json": "" }
    }
  EOT
  type        = string
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
