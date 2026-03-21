variable "client_id" {
  description = "Unique client identifier. Used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, qa, prod, workbench)."
  type        = string
}

variable "agency_principal_arn" {
  description = "ARN of the agency IAM principal (user or role) that is allowed to assume TerraformDeployRole."
  type        = string
}

variable "external_id" {
  description = "External ID required in the trust policy condition. Prevents confused deputy attacks. Must match the value used by the agency when calling sts:AssumeRole."
  type        = string
  sensitive   = true
}

variable "role_name" {
  description = "Name of the cross-account deploy role created in the client account."
  type        = string
  default     = "TerraformDeployRole"
}

variable "permissions_boundary_arn" {
  description = "ARN of an IAM permissions boundary policy to attach to TerraformDeployRole. Recommended to prevent privilege escalation. Leave empty to skip."
  type        = string
  default     = null
}

variable "use_admin_policy" {
  description = "Attach AdministratorAccess to TerraformDeployRole. Set to false to use the least-privilege inline policy instead. Recommended: false for prod, true only for initial bootstrapping."
  type        = bool
  default     = false
}

variable "create_break_glass_role" {
  description = "Create a read-only agency break-glass role that does not require ExternalId. Used for support and incident response."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
