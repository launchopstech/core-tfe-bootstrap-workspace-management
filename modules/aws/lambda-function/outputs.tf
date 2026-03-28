output "function_name" {
  description = "Name of the Lambda function."
  value       = module.lambda.lambda_function_name
}

output "function_arn" {
  description = "ARN of the Lambda function."
  value       = module.lambda.lambda_function_arn
}

output "invoke_arn" {
  description = "Invoke ARN for API Gateway integration."
  value       = module.lambda.lambda_function_invoke_arn
}

output "role_arn" {
  description = "ARN of the Lambda execution role."
  value       = module.lambda.lambda_role_arn
}

output "security_group_id" {
  description = "Security group ID (null if not VPC-attached)."
  value       = local.has_vpc ? aws_security_group.lambda[0].id : null
}
