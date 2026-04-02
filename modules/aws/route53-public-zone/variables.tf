variable "client_id" {
  description = "Client identifier."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "zone_name" {
  description = "Public Route53 hosted zone name to create."
  type        = string
}

variable "comment" {
  description = "Optional hosted zone comment."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
