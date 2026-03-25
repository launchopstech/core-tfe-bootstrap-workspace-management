output "preflight_enabled" {
  description = "Whether the bootstrap AWS-access preflight is enabled for this workspace."
  value       = var.enable_aws_preflight
}

output "account_id" {
  description = "AWS account ID confirmed by the bootstrap preflight."
  value       = var.enable_aws_preflight ? data.aws_caller_identity.current[0].account_id : null
}

output "caller_arn" {
  description = "ARN of the assumed role used by the bootstrap preflight."
  value       = var.enable_aws_preflight ? data.aws_caller_identity.current[0].arn : null
}

output "region" {
  description = "AWS region resolved during the bootstrap preflight."
  value       = var.enable_aws_preflight ? data.aws_region.current[0].name : null
}
