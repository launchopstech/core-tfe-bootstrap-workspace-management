variable "client_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  description = "Expected AWS account ID for this workspace. Used to verify OIDC is targeting the right account."
  type        = string
}
