resource "vault_kv_secret_v2" "workspace_id" {
  for_each = tfe_workspace.bootstrap_account
  provider = vault.infra-prod
  mount    = "cloud/metadata"
  name     = "aws/account/${each.key}/bootstrap-workspace-id"

  data_json = jsonencode({
    value       = each.value.id
    description = "Workspace id within the aws-core organization in Terraform Enterprise for the bootstrap account."
  })
}