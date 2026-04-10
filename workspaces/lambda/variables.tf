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

variable "secrets_workspace_name" {
  description = "Name of the Secrets workspace. Required when lambda_config_json.env_vars is non-empty."
  type        = string
  default     = ""
}

# ── Lambda configuration (object) ─────────────────────────────────────────────
variable "lambda_config_json" {
  description = <<-EOT
    Lambda configuration object. In .tf.json files, provide this as a nested
    JSON object, not a quoted JSON string. Expected shape:
    {
      "function_name_suffix": "my-worker",
      "package":     { "bucket": "lambda-code", "key": "worker-v1.zip", "create_bucket": false, "upload_seed_code": false },
      "runtime":     { "handler": "bootstrap", "runtime": "provided.al2023" },
      "performance": { "memory_mb": 256, "timeout_seconds": 30 },
      "environment": { "KEY": "value" },
      "env_vars": { "STRIPE_API_KEY": "stripe_api_key" },
      "network":     { "enabled": false },
      "logging":     { "retention_days": 90 },
      "iam":         { "additional_policy_json": "" }
    }

    When package.create_bucket = true, this workspace creates the configured
    S3 code bucket so an external build/deploy pipeline can upload the Lambda
    ZIP there. When package.upload_seed_code = true, this workspace also
    packages a seed ZIP from workspaces/seed_code and uploads it to
    the final artifact key so first-time applies can succeed before the real
    pipeline overwrites that same key.

    env_vars is optional. It maps Lambda environment-variable names to
    logical secret keys published by a sibling secrets workspace. Terraform
    injects the secret ARN as the env var value; Lambda code reads the actual
    secret value at runtime via GetSecretValue (process.env.MY_KEY contains
    the ARN, not the plaintext). This keeps secret material out of Terraform
    state and means out-of-band rotation propagates without workspace re-apply.
    The IAM role is automatically granted GetSecretValue on referenced secrets.
  EOT
  type        = any

  validation {
    condition     = can(keys(var.lambda_config_json))
    error_message = "lambda_config_json must be a JSON object, not a quoted JSON string."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
