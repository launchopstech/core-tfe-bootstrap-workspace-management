output "cluster_endpoint" {
  description = "Writer endpoint for the Aurora cluster."
  value       = module.aurora.cluster_endpoint
}

output "cluster_reader_endpoint" {
  description = "Read-only endpoint for the Aurora cluster."
  value       = module.aurora.cluster_reader_endpoint
}

output "cluster_arn" {
  value = module.aurora.cluster_arn
}

output "cluster_id" {
  value = module.aurora.cluster_id
}

output "cluster_master_user_secret_arn" {
  description = "Secrets Manager ARN for the master user password."
  value       = try(module.aurora.cluster_master_user_secret[0].secret_arn, null)
}

output "security_group_id" {
  value = module.aurora.security_group_id
}

output "db_resource_id" {
  description = "Cluster resource ID for IAM database authentication."
  value       = module.aurora.cluster_resource_id
}

output "db_username" {
  description = "Database master username."
  value       = var.db_username
}

output "db_name" {
  description = "Database name."
  value       = var.db_name
}
