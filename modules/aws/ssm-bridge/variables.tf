variable "client_id" {
  description = "Client identifier."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the bridge instance runs."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the bridge instance."
  type        = string
}

variable "rds_security_group_id" {
  description = "RDS security group ID the bridge may connect to."
  type        = string
}

variable "rds_port" {
  description = "Database port to allow from the bridge."
  type        = number
  default     = 5432
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt the bridge root volume."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the SSM bridge."
  type        = string
  default     = "t4g.nano"
}

variable "ami_id" {
  description = "Optional AMI ID override. Defaults to the latest Amazon Linux 2023 ARM64 AMI."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
