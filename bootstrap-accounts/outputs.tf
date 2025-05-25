output "bootstrap_account_workspaces" {
  value = { for k, v in tfe_workspace.bootstrap_account : k => v.id }
}