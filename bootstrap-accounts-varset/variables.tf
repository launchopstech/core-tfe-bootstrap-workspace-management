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
