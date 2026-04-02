output "api_endpoint" {
  description = "API Gateway invoke URL (null if gateway disabled)."
  value       = local.gateway_enabled ? module.api_gateway[0].stage_invoke_url : null
}

output "custom_domain_names" {
  description = "Map of custom domain names keyed by gateway.custom_domains entry key."
  value       = local.gateway_enabled ? module.api_gateway[0].custom_domain_names : {}
}

output "custom_domain_urls" {
  description = "Map of custom domain URLs keyed by gateway.custom_domains entry key."
  value       = local.gateway_enabled ? module.api_gateway[0].custom_domain_urls : {}
}

output "artifacts_bucket_name" {
  description = "S3 bucket name used for Lambda code artifacts."
  value       = local.create_artifacts_bucket ? module.code_bucket[0].bucket_id : local.resolved_artifacts_bucket
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
