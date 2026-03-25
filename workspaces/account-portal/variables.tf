variable "organization" {
  description = "HCP Terraform organization that owns the account portal and child project workspaces."
  type        = string
  default     = "core-aws"
}

variable "project_id" {
  description = "Project ID where client-facing child project workspaces should be created."
  type        = string
}

variable "project_vcs_repo_identifier" {
  description = "VCS repo identifier used for child project workspaces. Defaults to the control-plane repo unless explicitly overridden."
  type        = string
}

variable "project_vcs_oauth_token_id" {
  description = "OAuth token ID used for child project workspace VCS integration."
  type        = string
}

variable "project_requests_json" {
  description = "JSON document describing requested child project workspaces. Shape: {\"projects\": {\"vpc\": {\"enabled\": true, \"inputs\": {...}}, \"rds\": {\"enabled\": true, \"inputs\": {...}, \"depends_on\": [\"vpc\"]}}}."
  type        = string
  default     = "{\"projects\":{}}"
}

variable "client_admin_team_name" {
  description = "Optional HCP Terraform team name that should get write access to the client-facing project workspaces."
  type        = string
  default     = ""
}

variable "notification_emails_json" {
  description = "JSON-encoded list of notification email addresses."
  type        = string
  default     = "[]"
}

variable "bootstrap_global_variable_set_id" {
  description = "Optional global variable set ID to attach to child project workspaces."
  type        = string
  default     = null
}

variable "environment_variable_set_id" {
  description = "Optional environment-scoped variable set ID to attach to child project workspaces."
  type        = string
  default     = null
}

variable "security_tier_variable_set_id" {
  description = "Optional security-tier variable set ID to attach to child project workspaces."
  type        = string
  default     = null
}

variable "terraform_run_role_arn" {
  description = "AWS role ARN used by child project workspaces through HCP Terraform dynamic credentials."
  type        = string
}

variable "terraform_version" {
  description = "Terraform version to pin on child project workspaces."
  type        = string
  default     = "~> 1.9.0"
}

variable "client_id" {
  description = "Client identifier injected by the control plane."
  type        = string
}

variable "environment" {
  description = "Environment name injected by the control plane."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID backing this account portal."
  type        = string
}

variable "aws_account_name" {
  description = "Human-readable AWS account label."
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region injected by the control plane."
  type        = string
}

variable "security_tier" {
  description = "Security tier injected by the control plane."
  type        = string
  default     = null
}

variable "service_family" {
  description = "Logical service family injected by the control plane."
  type        = string
  default     = null
}
