variable "accounts" {
  description = "JSON object of AWS accounts containing account_id, product_name, and account_name"
  type        = map(any)
}

variable "aws_core_oauth_token_id" {
  description = "The oauth token id for the aws-core organization."
  type        = string
}

variable "enable_aws_core_failure_notification" {
  description = "Bool flag to enable or disable the notification attached to the bootstrap workspaces."
  type        = bool
}

variable "environment" {
  description = "The environment of AWS accounts."
  type        = string
}

variable "project_id" {
  description = "The ID of the project to place the workspace in."
  type        = string
}

variable "terraform_version" {
  description = "Version of Terraform to be set for the created workspaces."
  type        = string
  default     = "~> 1.0.0"
}

variable "tfe_prod_admin_token" {
  description = "User token for the Admin user. Used to invoke the bootstrap-varset-management workspace."
  type        = string
  sensitive   = true
}

variable "vault_approle_role_id" {
  description = "The approle role id used to authenticate via approle auth. This value can be found in vault here: ..."
  type        = string
}

variable "vault_approle_secret_id" {
  description = "The approle secret id used to authenticate via approle auth. This value can be found in vault here: ..."
  type        = string
  sensitive   = true
}