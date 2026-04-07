output "secret_arns" {
  description = "Map of secret ARNs keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}

output "secret_names" {
  description = "Map of secret names keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.name }
}

output "github_actions_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider used by repository roles, if any."
  value       = local.resolved_github_actions_oidc_provider_arn
}

output "github_actions_role_arns" {
  description = "Map of GitHub Actions repository role ARNs keyed by repo identifier."
  value       = { for repo_key, role in aws_iam_role.github_actions : repo_key => role.arn }
}

output "github_actions_repository_access" {
  description = "Repository AWS access metadata keyed by GitHub repository."
  value = merge(
    {
      for repo_key, repo in local.github_actions_oidc_repositories :
      repo_key => {
        mode                         = "oidc_role"
        role_arn                     = aws_iam_role.github_actions[repo_key].arn
        role_name                    = aws_iam_role.github_actions[repo_key].name
        access_key_id_secret_arn     = null
        secret_access_key_secret_arn = null
      }
    },
    {
      for repo_key, repo in local.github_actions_static_key_repositories :
      repo_key => {
        mode                         = "static_keys"
        role_arn                     = null
        role_name                    = null
        access_key_id_secret_arn     = aws_secretsmanager_secret.this[repo.aws_access.access_key_id_secret_key].arn
        secret_access_key_secret_arn = aws_secretsmanager_secret.this[repo.aws_access.secret_access_key_secret_key].arn
      }
    },
  )
}
