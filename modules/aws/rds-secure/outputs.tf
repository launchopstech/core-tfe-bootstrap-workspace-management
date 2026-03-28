output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_instance_arn" {
  value = module.db.db_instance_arn
}

output "db_instance_id" {
  value = module.db.db_instance_identifier
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for the master user password (managed by RDS)."
  value       = module.db.db_instance_master_user_secret_arn
}

output "security_group_id" {
  value = aws_security_group.rds.id
}

output "db_resource_id" {
  description = "DBI resource ID for IAM database authentication."
  value       = module.db.db_instance_resource_id
}

output "db_username" {
  description = "Database master username."
  value       = var.db_username
}

output "db_name" {
  description = "Database name."
  value       = var.db_name
}
