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

variable "dns_workspace_name" {
  description = "Name of the DNS workspace. Used when custom domains omit hosted_zone_id and should inherit the delegated zone from a sibling dns workspace."
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
        "custom_domains": {
          "primary": { "domain_name": "api.dev.example.com", "base_path": "" },
          "partner": { "domain_name": "partner-api.dev.example.com", "hosted_zone_id": "Z1234567890", "base_path": "api" }
        },
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
      "artifacts": { "bucket": "my-api-code", "key_prefix": "api", "version": "v1.2.3", "create_bucket": false, "upload_seed_code": false },
      "database":  { "proxy_enabled": true, "iam_username": "app" },
      "uploads":   { "enabled": true }
    }

    When artifacts.create_bucket = true, this workspace creates the configured
    S3 code bucket so an external build/deploy pipeline can upload Lambda ZIP
    artifacts there. When artifacts.upload_seed_code = true, this
    workspace also packages seed ZIPs from workspaces/seed_code
    and uploads them to the final artifact keys so first-time applies can
    succeed before the real pipeline overwrites those same keys.

    gateway.custom_domains is optional. Each entry assumes the hostname's
    Route53 hosted zone exists in the same AWS account. Each entry may either
    set hosted_zone_id directly or omit it and rely on dns_workspace_name to
    supply the delegated zone from a sibling dns workspace. This workspace
    will request and validate an ACM certificate, create the API Gateway
    custom domain, map it to the configured stage, and create the Route53
    alias record automatically.
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
