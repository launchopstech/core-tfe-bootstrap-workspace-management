output "function_name" {
  description = "Name of the Lambda function."
  value       = module.lambda.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function."
  value       = module.lambda.function_arn
}

output "invoke_arn" {
  description = "Invoke ARN of the Lambda function."
  value       = module.lambda.invoke_arn
}

output "role_arn" {
  description = "ARN of the Lambda execution role."
  value       = module.lambda.role_arn
}

output "security_group_id" {
  description = "Security group ID (null if not VPC-attached)."
  value       = module.lambda.security_group_id
}
