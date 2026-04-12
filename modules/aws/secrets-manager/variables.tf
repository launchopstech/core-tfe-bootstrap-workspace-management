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
  description = <<-EOT
    Logical secret definitions keyed by stable secret key.

    name_suffix is optional. When omitted the map key is used as the suffix
    (underscores replaced with hyphens), so the final AWS name is:
      <client_id>-<environment>-<key-with-hyphens>

    initial_value is written once on first apply (ignore_changes = [secret_string]).
    Subsequent changes to initial_value in config have no effect on the stored value.
    To rotate a value after initial creation, use aws secretsmanager put-secret-value
    or your CI/CD pipeline.

    Omit initial_value to create the container only. Set version_exists = true after
    populating the secret externally (put-secret-value or CI/CD). Consumer workspaces
    block at apply time unless every referenced secret key is present in
    secrets_with_versions — either because it has an initial_value managed by
    Terraform, or because version_exists = true has been set in config.
  EOT
  type = map(object({
    name_suffix             = optional(string, null)
    description             = optional(string, null)
    recovery_window_in_days = optional(number, 30)
    initial_value           = optional(string, null)
    version_exists          = optional(bool, false)
    tags                    = optional(map(string), {})
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
