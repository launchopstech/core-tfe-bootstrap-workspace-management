output "secret_arns" {
  description = "Map of Secrets Manager secret ARNs keyed by logical secret key."
  value       = module.secrets.secret_arns
}

output "secret_names" {
  description = "Map of Secrets Manager secret names keyed by logical secret key."
  value       = module.secrets.secret_names
}

output "secrets_with_versions" {
  description = "Set of logical secret keys that have a usable version. Consumer workspaces block at apply time unless every env_vars reference is present in this set."
  value       = module.secrets.secrets_with_versions
}

