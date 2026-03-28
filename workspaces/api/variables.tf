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
  description = "Name of the secure-baseline workspace."
  type        = string
}

variable "vpc_workspace_name" {
  description = "Name of the VPC workspace. Required when any lambda needs VPC or RDS proxy is enabled."
  type        = string
  default     = null
}

variable "rds_workspace_name" {
  description = "Name of the RDS workspace. Required when any lambda needs DB or RDS proxy is enabled."
  type        = string
  default     = null
}

# ── API configuration (object) ────────────────────────────────────────────────
variable "api_config_json" {
  description = <<-EOT
    API configuration object. In .tf.json files, provide this as a nested JSON
    object, not a quoted JSON string. All top-level sections are optional —
    omit a section to disable that component entirely.

    Expected shape:
    {
      "gateway": {
        "enabled": true,
        "cors": { "allowed_origins": ["*"] },
        "stage": { "name": "v1" },
        "authorizers": {
          "token": {
            "lambda_key": "authorizer",
            "auth_providers": { "okta": { "issuer_url": "...", "audiences": ["..."] } },
            "default_auth_provider": "okta"
          }
        },
        "routes": {
          "proxy":   { "path_part": "{proxy+}", "methods": ["ANY"], "integration_key": "crud",    "authorizer_key": "token" },
          "presign": { "path_part": "presign",  "methods": ["ANY"], "integration_key": "presign", "authorizer_key": "token" }
        }
      },
      "lambdas": {
        "crud":       { "function_name_suffix": "api-crud",       "memory_mb": 256, "timeout_seconds": 30, "needs_vpc": true,  "needs_db": true,  "needs_uploads": false },
        "presign":    { "function_name_suffix": "api-presign",    "memory_mb": 128, "timeout_seconds": 10, "needs_vpc": false, "needs_db": false, "needs_uploads": true  },
        "authorizer": { "function_name_suffix": "api-authorizer", "memory_mb": 128, "timeout_seconds": 10, "needs_vpc": false, "needs_db": false, "needs_uploads": false }
      },
      "artifacts": { "bucket": "my-artifacts", "key_prefix": "api", "version": "v1.2.3" },
      "database":  { "proxy_enabled": true, "iam_username": "app" },
      "uploads":   { "enabled": true }
    }
  EOT
  type        = any

  validation {
    condition     = can(keys(var.api_config_json))
    error_message = "api_config_json must be a JSON object, not a quoted JSON string."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
