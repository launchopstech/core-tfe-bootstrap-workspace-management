variable "client_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "cidr_block" {
  description = "VPC CIDR block."
  type        = string
}

variable "azs" {
  description = "List of availability zones."
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (one per AZ)."
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (one per AZ)."
  type        = list(string)
}

variable "database_subnets" {
  description = "CIDR blocks for isolated database subnets (one per AZ). Leave empty to skip database subnet group creation."
  type        = list(string)
  default     = []
}

variable "logs_bucket_arn" {
  description = "ARN of the platform logs S3 bucket from secure-baseline. Used for VPC flow logs."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
