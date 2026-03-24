variable "accounts" {
  description = "Map of AWS account metadata keyed by account ID."
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

variable "project_id" {
  description = "The ID of the agency-internal project to place bootstrap workspaces in (hidden from client)."
  type        = string
}

variable "team_project_id" {
  description = "The ID of the client-facing team project to place team workspaces in."
  type        = string
}

variable "terraform_version" {
  description = "Version of Terraform to be set for the created workspaces."
  type        = string
  default     = "~> 1.9"
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
