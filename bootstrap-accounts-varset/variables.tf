variable "organization" {
  description = "HCP Terraform organization that owns the projects and variable sets."
  type        = string
  default     = "core-aws"
}

variable "control_plane_sensitive_variables" {
  description = "Sensitive Terraform variables to place in the optional control-plane secrets variable set."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "portal_automation_token" {
  description = "HCP Terraform token injected as TFE_TOKEN into all team-* projects. Account-portal workspaces use this to create child deployer workspaces. Use an owners or platform-automation team token."
  type        = string
  sensitive   = true
  default     = ""
}

variable "portal_automation_enabled" {
  description = "Set to true when portal_automation_token is provided. Controls creation of the portal-automation-token variable set and project attachments. Kept non-sensitive so it can drive for_each and count expressions."
  type        = bool
  default     = false
}
