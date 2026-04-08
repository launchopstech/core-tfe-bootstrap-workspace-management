variable "name_prefix" {
  description = "Prefix used when constructing secret names."
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

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
