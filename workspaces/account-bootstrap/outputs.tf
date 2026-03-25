output "preflight_enabled" {
  description = "Whether the bootstrap AWS-access preflight is enabled for this workspace."
  value       = var.enable_aws_preflight
}

output "account_id" {
  description = "AWS account ID confirmed by the bootstrap preflight."
  value       = var.enable_aws_preflight ? module.aws_preflight[0].account_id : null
}

output "caller_arn" {
  description = "ARN of the assumed role used by the bootstrap preflight."
  value       = var.enable_aws_preflight ? module.aws_preflight[0].caller_arn : null
}

output "region" {
  description = "AWS region resolved during the bootstrap preflight."
  value       = var.enable_aws_preflight ? module.aws_preflight[0].region : null
}
