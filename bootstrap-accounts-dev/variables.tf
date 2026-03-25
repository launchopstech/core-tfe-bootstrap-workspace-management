variable "organization" {
  description = "HCP Terraform organization that owns the control-plane workspaces."
  type        = string
  default     = "core-aws"
}

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
  default     = "~> 1.9.0"
}

variable "bootstrap_varsets_workspace_name" {
  description = "Workspace name that publishes the bootstrap variable-set outputs."
  type        = string
  default     = "00-bootstrap-account-workspace-management"
}

variable "notification_emails" {
  description = "Email addresses to notify on workspace run failures."
  type        = list(string)
  default     = []
}
