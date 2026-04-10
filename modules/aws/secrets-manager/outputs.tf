output "secret_arns" {
  description = "Map of secret ARNs keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}

output "secret_names" {
  description = "Map of secret names keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.name }
}

output "secrets_with_versions" {
  description = "Set of logical secret keys that have a usable version: either a Terraform-managed initial_value, or version_exists = true set after external population. Consumer workspaces block at apply time unless every referenced secret key is in this set."
  value = toset(concat(
    keys(aws_secretsmanager_secret_version.initial),
    [for k, v in var.secret_definitions : k if try(v.version_exists, false)]
  ))
}
