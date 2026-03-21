output "logs_bucket_id" {
  description = "S3 bucket name for platform logs. Used by service modules that need a log destination."
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "S3 bucket ARN for platform logs."
  value       = aws_s3_bucket.logs.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID. Null if GuardDuty is disabled."
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "security_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts. Null if notifications are disabled."
  value       = var.enable_notifications ? aws_sns_topic.security_alerts[0].arn : null
}

output "config_recorder_name" {
  description = "AWS Config recorder name. Null if Config is disabled."
  value       = var.enable_config ? aws_config_configuration_recorder.main[0].name : null
}

output "access_analyzer_arn" {
  description = "IAM Access Analyzer ARN. Null if disabled."
  value       = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.main[0].arn : null
}
