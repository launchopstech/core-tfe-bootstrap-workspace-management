output "account_id" {
  description = "AWS account ID confirmed via OIDC auth."
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "ARN of the assumed role used by this workspace."
  value       = data.aws_caller_identity.current.arn
}

output "region" {
  description = "AWS region this workspace is deployed into."
  value       = data.aws_region.current.name
}
