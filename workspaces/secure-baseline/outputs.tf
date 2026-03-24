output "kms_key_arn" {
  description = "KMS key ARN passed in from the CFN bootstrap — re-exported for downstream workspaces."
  value       = var.kms_key_arn
}

output "logs_bucket_id" {
  value = module.secure_baseline.logs_bucket_id
}

output "logs_bucket_arn" {
  value = module.secure_baseline.logs_bucket_arn
}

output "guardduty_detector_id" {
  value = module.secure_baseline.guardduty_detector_id
}

output "security_alerts_topic_arn" {
  value = module.secure_baseline.security_alerts_topic_arn
}
