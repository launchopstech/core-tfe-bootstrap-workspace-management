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

# ── Aurora-only outputs ─────────────────────────────────────────────────────
output "db_reader_endpoint" {
  description = "Read-only endpoint (Aurora only, null for single instance)."
  value       = var.enable_cluster ? module.aurora[0].cluster_reader_endpoint : null
}
