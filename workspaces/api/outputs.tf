output "api_endpoint" {
  description = "API Gateway invoke URL (null if gateway disabled)."
  value       = local.gateway_enabled ? module.api_gateway[0].stage_invoke_url : null
}

output "api_id" {
  description = "API Gateway REST API ID (null if gateway disabled)."
  value       = local.gateway_enabled ? module.api_gateway[0].api_id : null
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint (null if proxy disabled)."
  value       = try(module.rds_proxy[0].proxy_endpoint, null)
}

output "lambda_arns" {
  description = "Map of Lambda function ARNs keyed by lambda config key."
  value       = { for k, v in module.lambdas : k => v.function_arn }
}

output "uploads_bucket_arn" {
  description = "ARN of the uploads S3 bucket (null if uploads disabled)."
  value       = try(module.uploads_bucket[0].bucket_arn, null)
}
