output "oidc_provider_arn" {
  description = "ARN of the OIDC provider used by this workspace, if any."
  value       = module.iam_access.oidc_provider_arn
}

output "oidc_role_arns" {
  description = "Map of federated OIDC role ARNs keyed by role key."
  value       = module.iam_access.oidc_role_arns
}

output "access_bindings" {
  description = "Access binding metadata keyed by role key."
  value       = module.iam_access.access_bindings
}
