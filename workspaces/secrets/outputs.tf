output "secret_arns" {
  description = "Map of Secrets Manager secret ARNs keyed by logical secret key."
  value       = module.secrets.secret_arns
}

output "secret_names" {
  description = "Map of Secrets Manager secret names keyed by logical secret key."
  value       = module.secrets.secret_names
}
