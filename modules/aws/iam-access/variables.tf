variable "name_prefix" {
  description = "Prefix used when constructing federated role names."
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

variable "oidc_issuer_url" {
  description = "OIDC issuer URL used in federated role trust policies."
  type        = string
  default     = ""
}

variable "oidc_provider_arn" {
  description = "Existing IAM OIDC provider ARN to reuse. Leave null to create one from oidc_client_id_list and oidc_thumbprint_list."
  type        = string
  default     = null
}

variable "oidc_client_id_list" {
  description = "OIDC client IDs for a provider created by this module."
  type        = list(string)
  default     = []
}

variable "oidc_thumbprint_list" {
  description = "OIDC thumbprints for a provider created by this module."
  type        = list(string)
  default     = []
}

variable "oidc_roles" {
  description = "Federated OIDC roles keyed by stable role key."
  type = map(object({
    role_name_suffix    = optional(string, null)
    description         = optional(string, null)
    managed_policy_arns = optional(list(string), [])
    inline_policy_json  = optional(string, "")
    audience_values     = optional(list(string), ["sts.amazonaws.com"])
    subject_claims      = optional(list(string), [])
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
