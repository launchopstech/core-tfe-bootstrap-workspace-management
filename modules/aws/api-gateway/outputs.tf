output "api_id" {
  description = "ID of the API Gateway REST API."
  value       = aws_api_gateway_rest_api.this.id
}

output "api_execution_arn" {
  description = "Execution ARN of the API Gateway REST API."
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "stage_invoke_url" {
  description = "Invoke URL for the deployed stage."
  value       = aws_api_gateway_stage.this.invoke_url
}
