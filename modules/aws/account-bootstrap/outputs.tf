output "terraform_deploy_role_arn" {
  description = "ARN of the TerraformDeployRole. Used by HCP Terraform workspace assume_role config."
  value       = aws_iam_role.terraform_deploy.arn
}

output "terraform_deploy_role_name" {
  description = "Name of the TerraformDeployRole."
  value       = aws_iam_role.terraform_deploy.name
}

output "break_glass_role_arn" {
  description = "ARN of the read-only break-glass role. Null if create_break_glass_role is false."
  value       = var.create_break_glass_role ? aws_iam_role.break_glass[0].arn : null
}

output "kms_key_arn" {
  description = "ARN of the platform KMS key. Used by secure-baseline and service modules for encryption."
  value       = aws_kms_key.platform.arn
}

output "kms_key_id" {
  description = "Key ID of the platform KMS key."
  value       = aws_kms_key.platform.key_id
}

output "kms_key_alias" {
  description = "Alias of the platform KMS key."
  value       = aws_kms_alias.platform.name
}

output "account_id" {
  description = "AWS account ID where bootstrap resources were created."
  value       = data.aws_caller_identity.current.account_id
}
