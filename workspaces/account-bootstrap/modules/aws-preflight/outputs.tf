output "account_id" {
  description = "AWS account ID confirmed by the bootstrap preflight."
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "ARN of the assumed role used by the bootstrap preflight."
  value       = data.aws_caller_identity.current.arn
}

output "region" {
  description = "AWS region resolved during the bootstrap preflight."
  value       = data.aws_region.current.name
}
