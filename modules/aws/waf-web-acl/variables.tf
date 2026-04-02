variable "name" {
  description = "Name of the WAFv2 Web ACL."
  type        = string
}

variable "client_id" {
  description = "Client identifier."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "description" {
  description = "Optional Web ACL description."
  type        = string
  default     = null
}

variable "scope" {
  description = "WAF scope. v1 supports REGIONAL only."
  type        = string
}

variable "default_action" {
  description = "Default action for unmatched requests."
  type        = string
}

variable "attachment" {
  description = "Attachment behavior for this Web ACL."
  type = object({
    mode         = string
    resource_arn = optional(string, null)
  })
  default = {
    mode = "target"
  }
}

variable "logging" {
  description = "Mandatory WAF logging configuration."
  type = object({
    retention_days   = number
    redacted_headers = list(string)
  })
}

variable "managed_rule_groups" {
  description = "Managed rule groups to include in the Web ACL."
  type = map(object({
    priority        = number
    vendor_name     = string
    name            = string
    override_action = optional(string, "none")
    excluded_rules  = optional(list(string), [])
  }))
  default = {}
}

variable "rate_rules" {
  description = "Rate-based rules keyed by logical name."
  type = map(object({
    priority           = number
    limit              = number
    aggregate_key_type = optional(string, "IP")
    action             = optional(string, "block")
  }))
  default = {}
}

variable "ip_sets" {
  description = "IP sets keyed by logical name."
  type = map(object({
    addresses          = list(string)
    ip_address_version = optional(string, "IPV4")
    description        = optional(string, null)
  }))
  default = {}
}

variable "ip_rules" {
  description = "IP allow, block, or count rules keyed by logical name."
  type = map(object({
    priority   = number
    ip_set_key = string
    action     = optional(string, "block")
  }))
  default = {}
}

variable "geo_rules" {
  description = "Geo match rules keyed by logical name."
  type = map(object({
    priority      = number
    country_codes = list(string)
    action        = optional(string, "block")
  }))
  default = {}
}

variable "match_rules" {
  description = "Simple byte match rules keyed by logical name."
  type = map(object({
    priority              = number
    action                = optional(string, "block")
    search_string         = string
    positional_constraint = optional(string, "CONTAINS")
    field_to_match = object({
      type              = string
      name              = optional(string)
      oversize_handling = optional(string, "CONTINUE")
    })
    text_transformations = optional(list(object({
      priority = number
      type     = string
    })), [{ priority = 0, type = "NONE" }])
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
