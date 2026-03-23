variable "client_id" { type = string }
variable "environment" { type = string }
variable "bucket_name" { type = string }
variable "kms_key_arn" { type = string }

variable "enable_versioning" {
  type    = bool
  default = true
}

variable "force_destroy" {
  description = "Allow bucket deletion even if objects exist. Never true in prod."
  type        = bool
  default     = false
}

variable "lifecycle_rules_enabled" {
  type    = bool
  default = true
}

variable "expiration_days" {
  type    = number
  default = 365
}

variable "tags" {
  type    = map(string)
  default = {}
}
