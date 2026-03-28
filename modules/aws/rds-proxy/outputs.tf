output "proxy_endpoint" {
  description = "RDS Proxy endpoint for database connections."
  value       = module.rds_proxy.proxy_endpoint
}

output "proxy_arn" {
  description = "ARN of the RDS Proxy."
  value       = module.rds_proxy.proxy_arn
}

output "proxy_resource_id" {
  description = "RDS Proxy resource ID (prx-...) for IAM rds-db:connect policies."
  value       = element(split(":", module.rds_proxy.proxy_arn), 6)
}

output "security_group_id" {
  description = "Security group ID of the RDS Proxy."
  value       = aws_security_group.proxy.id
}
