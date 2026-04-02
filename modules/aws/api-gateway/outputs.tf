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

output "stage_arn" {
  description = "ARN of the deployed API Gateway stage."
  value       = aws_api_gateway_stage.this.arn
}

output "custom_domain_names" {
  description = "Map of custom domain names keyed by custom_domains entry key."
  value       = { for key, domain in aws_api_gateway_domain_name.custom : key => domain.domain_name }
}

output "custom_domain_urls" {
  description = "Map of custom domain URLs keyed by custom_domains entry key."
  value       = local.custom_domain_urls
}
