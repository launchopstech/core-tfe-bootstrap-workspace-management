variable "client_id" {
  description = "Unique client identifier."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, qa, prod, workbench)."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the platform KMS key created by the CFN bootstrap (cfn-terraform-bootstrap.yaml). Used to encrypt logs, SNS, and Config delivery."
  type        = string
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for management event logging."
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config for resource configuration recording. SINGLETON: only 1 active recorder per account per region. Set to false if another client's workspace already created a recorder in this account."
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable GuardDuty threat detection. SINGLETON: only 1 detector per account per region. Set to false if another client's workspace already created a detector in this account."
  type        = bool
  default     = true
}

variable "enable_guardduty_eks_audit" {
  description = "Enable GuardDuty EKS audit log monitoring. Requires EKS clusters to exist or be planned."
  type        = bool
  default     = false
}

variable "enable_security_hub" {
  description = "Enable Security Hub with CIS and FSBP standards. SINGLETON: only 1 per account. Set to false if another client's workspace already enabled Security Hub in this account. Requires GuardDuty and Config to be enabled first."
  type        = bool
  default     = true
}

variable "enable_access_analyzer" {
  description = "Enable IAM Access Analyzer for account-level policy analysis. SINGLETON: only 1 ACCOUNT-type analyzer per account per region (quota enforced). Set to false if another client's workspace already created an analyzer in this account."
  type        = bool
  default     = true
}

variable "enable_notifications" {
  description = "Enable SNS security alert notifications."
  type        = bool
  default     = true
}

variable "security_alert_emails" {
  description = "List of email addresses to receive security alert notifications (GuardDuty findings, Config non-compliance)."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain logs in S3 before expiration. Minimum 365 recommended for compliance."
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days >= 90
    error_message = "log_retention_days must be at least 90."
  }
}

variable "tags" {
  description = "Tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
