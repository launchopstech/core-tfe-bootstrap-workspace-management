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

# ── DNS configuration (object) ────────────────────────────────────────────────
variable "dns_config_json" {
  description = <<-EOT
    DNS configuration object. In .tf.json files, provide this as a nested JSON
    object, not a quoted JSON string.

    Expected shape:
    {
      "zone_name": "dev.example.com",
      "comment": "Delegated development public zone"
    }

    This workspace manages only the delegated public hosted zone in v1.
    Parent-zone NS delegation remains a manual step outside this workspace.
  EOT
  type        = any

  validation {
    condition     = can(keys(var.dns_config_json))
    error_message = "dns_config_json must be a JSON object, not a quoted JSON string."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
