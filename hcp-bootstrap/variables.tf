variable "organization" {
  description = "HCP Terraform organization that will own the control-plane workspaces."
  type        = string
  default     = "core-aws"
}

variable "terraform_version" {
  description = "Terraform version to pin on created control-plane workspaces."
  type        = string
  default     = "~> 1.0.0"
}

variable "vcs_repo_identifier" {
  description = "VCS repository identifier in the format expected by HCP Terraform, for example org/repo."
  type        = string
}

variable "vcs_branch" {
  description = "Default VCS branch for the control-plane workspaces."
  type        = string
  default     = "main"
}

variable "vcs_oauth_token_id" {
  description = "OAuth token ID used by HCP Terraform to read the VCS repository."
  type        = string
}
