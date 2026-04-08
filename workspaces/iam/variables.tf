# -- Identity (injected by account portal) -------------------------------------
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

# -- Informational (injected by account portal, not required for function) -----
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

variable "hcp_terraform_organization" {
  description = "HCP Terraform organization name."
  type        = string
  default     = "core-aws"
}

variable "iam_config_json" {
  description = <<-EOT
    IAM access configuration object. In .tf.json files, provide this as a
    nested JSON object, not a quoted JSON string.

    Expected shape:
    {
      "oidc": {
        "issuer_url": "https://token.actions.githubusercontent.com",
        "client_id_list": ["sts.amazonaws.com"],
        "thumbprint_list": ["6938fd4d98bab03faadb97b34396831e3780aea1"],
        "roles": {
          "artifact_publisher": {
            "role_name_suffix": "artifact-publisher",
            "subject_claims": ["repo:org/repo:*"],
            "managed_policy_arns": [],
            "inline_policy_json": {
              "Version": "2012-10-17",
              "Statement": []
            }
          }
        }
      }
    }

    This workspace owns identity access concerns such as OIDC providers and
    federated IAM roles. Runtime application secrets belong in the separate
    secrets workspace. inline_policy_json may be provided either as a nested
    JSON object (preferred in .tf.json) or as a JSON string.
  EOT
  type        = any

  validation {
    condition     = can(keys(var.iam_config_json))
    error_message = "iam_config_json must be a JSON object, not a quoted JSON string."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
