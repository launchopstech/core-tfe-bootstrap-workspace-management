output "oidc_provider_arn" {
  description = "ARN of the OIDC provider used by federated roles, if any."
  value       = local.resolved_oidc_provider_arn
}

output "oidc_role_arns" {
  description = "Map of federated OIDC role ARNs keyed by role key."
  value       = { for role_key, role in aws_iam_role.oidc : role_key => role.arn }
}

output "access_bindings" {
  description = "Access binding metadata keyed by role key."
  value = {
    for role_key, role in local.oidc_roles :
    role_key => {
      mode            = "oidc_role"
      role_arn        = aws_iam_role.oidc[role_key].arn
      role_name       = aws_iam_role.oidc[role_key].name
      audience_values = local.oidc_role_audience_values[role_key]
      subject_claims  = role.subject_claims
    }
  }
}
