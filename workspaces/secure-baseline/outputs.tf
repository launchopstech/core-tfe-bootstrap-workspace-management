output "terraform_deploy_role_arn" {
  value = module.account_bootstrap.terraform_deploy_role_arn
}

output "kms_key_arn" {
  value = module.account_bootstrap.kms_key_arn
}

output "kms_key_id" {
  value = module.account_bootstrap.kms_key_id
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
