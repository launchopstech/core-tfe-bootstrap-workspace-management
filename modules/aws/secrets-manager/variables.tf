variable "name_prefix" {
  description = "Prefix used when constructing secret names and GitHub Actions role names."
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

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt Secrets Manager secrets."
  type        = string
}

variable "secret_definitions" {
  description = "Logical secret definitions keyed by stable secret key."
  type = map(object({
    name_suffix             = string
    description             = optional(string, null)
    recovery_window_in_days = optional(number, 30)
    tags                    = optional(map(string), {})
  }))
  default = {}
}

variable "github_actions" {
  description = "GitHub Actions AWS access configuration."
  type = object({
    oidc_provider_arn = optional(string, null)
    repositories = optional(map(object({
      aws_access = object({
        mode                         = string
        role_name_suffix             = optional(string, null)
        managed_policy_arns          = optional(list(string), [])
        inline_policy_json           = optional(string, "")
        subject_claims               = optional(list(string), [])
        access_key_id_secret_key     = optional(string, null)
        secret_access_key_secret_key = optional(string, null)
      })
    })), {})
  })
  default = {
    repositories = {}
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
