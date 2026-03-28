# ── Original output names (consumed by tfe_outputs in other workspaces) ──────
output "db_instance_endpoint" {
  description = "Database connection endpoint."
  value       = var.enable_cluster ? module.aurora[0].cluster_endpoint : module.rds[0].db_instance_endpoint
}

output "db_instance_arn" {
  description = "ARN of the database instance or cluster."
  value       = var.enable_cluster ? module.aurora[0].cluster_arn : module.rds[0].db_instance_arn
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for the master user password."
  value       = var.enable_cluster ? module.aurora[0].cluster_master_user_secret_arn : module.rds[0].db_secret_arn
}

output "security_group_id" {
  value = var.enable_cluster ? module.aurora[0].security_group_id : module.rds[0].security_group_id
}

# ── Identifier outputs (consumed by RDS Proxy in the api workspace) ────────
output "db_identifier" {
  description = "Database instance identifier (single) or cluster identifier (Aurora)."
  value       = var.enable_cluster ? module.aurora[0].cluster_id : module.rds[0].db_instance_id
}

output "enable_cluster" {
  description = "Whether this RDS workspace deployed an Aurora cluster."
  value       = var.enable_cluster
}

# ── IAM auth outputs (consumed by api workspace for rds-db:connect) ─────────
output "db_resource_id" {
  description = "DBI resource ID (single) or cluster resource ID (Aurora) for IAM auth."
  value       = var.enable_cluster ? module.aurora[0].db_resource_id : module.rds[0].db_resource_id
}

output "db_username" {
  description = "Database master username."
  value       = var.db_username
}

output "db_name" {
  description = "Database name."
  value       = var.db_name
}

# ── Aurora-only outputs ─────────────────────────────────────────────────────
output "db_reader_endpoint" {
  description = "Read-only endpoint (Aurora only, null for single instance)."
  value       = var.enable_cluster ? module.aurora[0].cluster_reader_endpoint : null
}
