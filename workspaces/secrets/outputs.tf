output "secret_arns" {
  description = "Map of Secrets Manager secret ARNs keyed by logical secret key."
  value       = module.secrets.secret_arns
}

output "secret_names" {
  description = "Map of Secrets Manager secret names keyed by logical secret key."
  value       = module.secrets.secret_names
}

output "github_actions_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider used by this workspace, if any."
  value       = module.secrets.github_actions_oidc_provider_arn
}

output "github_actions_role_arns" {
  description = "Map of GitHub Actions role ARNs keyed by repository."
  value       = module.secrets.github_actions_role_arns
}

output "github_actions_repository_access" {
  description = "Repository AWS access metadata keyed by GitHub repository."
  value       = module.secrets.github_actions_repository_access
}
