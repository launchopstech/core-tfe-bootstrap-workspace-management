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

variable "tfe_prod_admin_token" {
  description = "Terraform Enterprise Admin user. Used to create the bootstrap-workspace-management workspaces."
  type        = string
}

variable "vault_approle_role_id" {
  description = "This value can be found in vault approle auth."
  type        = string
}

variable "vault_approle_secret_id" {
  description = "This value can be found in vault approle auth."
  type        = string
}  

variable "TFE_TOKEN" {
  description = "Terraform Enterprise token."
  type        = string
  default = "fvyEROsplGUeIw.atlasv1.8wDJ4jyBbeuzAZt8JSKUTIzk6WLRaKrx8mvDhLp7hkUYMfhFWiLiSQyRrzW48zFz03I"
}
