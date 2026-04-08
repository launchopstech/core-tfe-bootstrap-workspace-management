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

# ── Organization / dependency workspace names ─────────────────────────────────
variable "hcp_terraform_organization" {
  description = "HCP Terraform organization name."
  type        = string
  default     = "core-aws"
}

variable "secure_baseline_workspace_name" {
  description = "Name of the secure-baseline workspace (for KMS key ARN)."
  type        = string
}

# ── Secrets configuration (object) ────────────────────────────────────────────
variable "secrets_config_json" {
  description = <<-EOT
    Secrets configuration object. In .tf.json files, provide this as a nested
    JSON object, not a quoted JSON string.

    Expected shape:
    {
      "secrets": {
        "stripe_api_key": {
          "name_suffix": "stripe-api-key",
          "description": "Stripe server-side API key",
          "recovery_window_in_days": 30,
          "tags": {
            "rotation_owner": "app-team"
          }
        }
      }
    }

    This workspace is metadata-only for secret values. Terraform creates
    Secrets Manager secret containers, but it does not write secret values into
    Secrets Manager. Identity concerns such as OIDC providers and federated IAM
    roles belong in the separate iam workspace.
  EOT
  type        = any

  validation {
    condition     = can(keys(var.secrets_config_json))
    error_message = "secrets_config_json must be a JSON object, not a quoted JSON string."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
