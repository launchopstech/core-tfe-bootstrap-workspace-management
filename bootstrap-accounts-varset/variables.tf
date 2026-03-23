variable "control_plane_sensitive_variables" {
  description = "Sensitive Terraform variables to place in the optional control-plane secrets variable set."
  type        = map(string)
  sensitive   = true
  default     = {}
}
