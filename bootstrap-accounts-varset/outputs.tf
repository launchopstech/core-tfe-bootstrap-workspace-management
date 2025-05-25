output "bootstrap_accounts_varset" {
  value = tfe_variable_set.bootstrap_accounts.id
}

output "bootstrap_accounts_dt_varset" {
  value = tfe_variable_set.bootstrap_accounts_dt.id
}

output "bootstrap_accounts_qa_varset" {
  value = tfe_variable_set.bootstrap_accounts_qa.id
}

output "bootstrap_accounts_prod_varset" {
  value = tfe_variable_set.bootstrap_accounts_prod.id
}