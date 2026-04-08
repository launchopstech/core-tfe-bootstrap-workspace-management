output "secret_arns" {
  description = "Map of secret ARNs keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}

output "secret_names" {
  description = "Map of secret names keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.name }
}
