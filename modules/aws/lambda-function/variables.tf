variable "function_name" {
  description = "Name of the Lambda function."
  type        = string
}

variable "client_id" {
  description = "Client identifier."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, qa, prod, workbench)."
  type        = string
}

variable "description" {
  description = "Description of the Lambda function."
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package."
  type        = string
}

variable "s3_key" {
  description = "S3 object key for the Lambda deployment package."
  type        = string
}

variable "s3_object_version" {
  description = "Optional S3 object version for the Lambda deployment package."
  type        = string
  default     = null
}

variable "handler" {
  description = "Lambda function handler."
  type        = string
  default     = "bootstrap"
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "provided.al2023"
}

variable "memory_size" {
  description = "Amount of memory in MB available to the Lambda function."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Lambda function timeout in seconds."
  type        = number
  default     = 30
}

variable "environment_variables" {
  description = "Map of environment variables for the Lambda function."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID for VPC-attached Lambda. Leave null for non-VPC Lambdas."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for VPC-attached Lambda."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "KMS key ARN for CloudWatch log group encryption."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 90
}

variable "additional_policy_json" {
  description = "Optional inline IAM policy JSON for service-specific permissions."
  type        = string
  default     = ""
}

variable "attach_additional_policy_json" {
  description = "Whether to attach additional_policy_json. Set this explicitly when the policy JSON may be unknown during plan."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
