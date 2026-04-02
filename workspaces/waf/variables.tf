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

# ── WAF configuration (object) ────────────────────────────────────────────────
variable "waf_config_json" {
  description = <<-EOT
    WAF configuration object. In .tf.json files, provide this as a nested JSON
    object, not a quoted JSON string.

    Expected shape:
    {
      "default_action": "allow",
      "scope": "REGIONAL",
      "attachment": {
        "mode": "target"
      },
      "logging": {
        "enabled": true,
        "retention_days": 30,
        "redacted_headers": ["authorization"]
      },
      "managed_rule_groups": {
        "common": {
          "priority": 100,
          "vendor_name": "AWS",
          "name": "AWSManagedRulesCommonRuleSet",
          "override_action": "none",
          "excluded_rules": []
        }
      },
      "rate_rules": {
        "global": {
          "priority": 200,
          "limit": 2000,
          "aggregate_key_type": "IP",
          "action": "block"
        }
      },
      "ip_sets": {},
      "ip_rules": {},
      "geo_rules": {},
      "match_rules": {}
    }

    v1 is REGIONAL only and always configures CloudWatch WAF logging.
    attachment.mode may be:
    - "target": the protected service attaches the Web ACL
    - "self": this workspace attaches the Web ACL using attachment.resource_arn
  EOT
  type        = any

  validation {
    condition     = can(keys(var.waf_config_json))
    error_message = "waf_config_json must be a JSON object, not a quoted JSON string."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
