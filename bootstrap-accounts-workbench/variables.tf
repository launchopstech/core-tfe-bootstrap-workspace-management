variable "aws_core_oauth_token_id" {
  description = "The auth token id for aws core oauth."
  type        = string
}

variable "enable_aws_core_failure_notification" {
  description = "Set this flag to enable/disable notification attached to the bootstrap mechanism that issues the error notification in bootstrap workspace for aws-core team."
  type        = bool
}

variable "terraform_version" {
  description = "Terraform version to be set for the created workspaces."
  type        = string
}

variable "bootstrap_varsets_workspace_name" {
  description = "Workspace name that publishes the bootstrap variable-set outputs."
  type        = string
  default     = "00-bootstrap-account-workspace-management"
}

variable "project_id_override" {
  description = "Optional override for the project ID used to create bootstrap account workspaces."
  type        = string
  default     = null
}

variable "environment" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}

variable "tfe_prod_admin_token" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}

variable "vault_approle_role_id" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}

variable "vault_approle_secret_id" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}

variable "vault_addr" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}

variable "vault_config_username" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}

variable "vault_config_password" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}

variable "TFE_TOKEN" {
  description = "Deprecated compatibility input. Ignored by this root module."
  type        = string
  default     = null
}
