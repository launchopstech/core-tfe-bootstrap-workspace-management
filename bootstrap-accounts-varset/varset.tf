################################################################################
# bootstrap-accounts-varset
################################################################################

resource "tfe_variable_set" "bootstrap_accounts" {
  name         = "bootstrap-accounts"
  description  = "WRITTEN BY AUTOMATION: Shared variables used by each bootstrap-account workspace."
  organization = "core-aws"
}

resource "tfe_variable" "aws_master_account_id" {
  key            = "aws_master_account_id"
  value          = "889851937279"
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts.id
}

resource "tfe_variable" "vault_approle_role_id" {
  key            = "vault_approle_role_id"
  value          = "POPULATE IN UI"
  description    = "The approle role id used to authenticate via approle auth."
  category       = "terraform"
  sensitive      = true
  variable_set_id = tfe_variable_set.bootstrap_accounts.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_approle_secret_id" {
  key            = "vault_approle_secret_id"
  value          = "POPULATE IN UI"
  description    = "The approle secret id used to authenticate via approle auth."
  category       = "terraform"
  sensitive      = true
  variable_set_id = tfe_variable_set.bootstrap_accounts.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_cc_prod_username" {
  key            = "vault_cc_prod_username"
  value          = "POPULATE IN UI"
  description    = "Username used to authenticate to vault-cc-prod."
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_cc_prod_password" {
  key            = "vault_cc_prod_password"
  value          = "POPULATE IN UI"
  description    = "Password used to authenticate to vault-cc-prod."
  category       = "terraform"
  sensitive      = true
  variable_set_id = tfe_variable_set.bootstrap_accounts.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_addr_dt" {
  key            = "vault_addr_dt"
  value          = "https://vault-cc.dt.duke-energy.com"
  description    = "The address to the vault cluster."
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts.id
}

################################################################################
# sbx & dev varsets
################################################################################

resource "tfe_variable_set" "bootstrap_accounts_dt" {
  name         = "bootstrap-accounts-dt"
  description  = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for SBX and DEV accounts."
  organization = "core-aws"
}

resource "tfe_project_variable_set" "bootstrap_accounts_sbx" {
  variable_set_id = tfe_variable_set.bootstrap_accounts_dt.id
  project_id      = tfe_project.bootstrap_sbx.id
}

resource "tfe_project_variable_set" "bootstrap_accounts_dev" {
  variable_set_id = tfe_variable_set.bootstrap_accounts_dt.id
  project_id      = tfe_project.bootstrap_dev.id
}

resource "tfe_variable" "vault_config_username_dt" {
  key            = "vault_config_username"
  value          = "core-aws"
  description    = "Username to authenticate to Vault."
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts_dt.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_config_password_dt" {
  key            = "vault_config_password"
  value          = "POPULATE IN UI"
  description    = "Password to authenticate to Vault."
  category       = "terraform"
  sensitive      = true
  variable_set_id = tfe_variable_set.bootstrap_accounts_dt.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_addr_dt_alt" {
  key            = "vault_addr"
  value          = "http://localhost:8200"
  description    = "Vault address for SBX/DEV"
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts_dt.id
  depends_on     = [tfe_variable_set.bootstrap_accounts_dt]
}

################################################################################
# qa varset
################################################################################

resource "tfe_variable_set" "bootstrap_accounts_qa" {
  name         = "bootstrap-accounts-qa"
  description  = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for QA accounts."
  organization = "core-aws"
}

resource "tfe_project_variable_set" "bootstrap_accounts_qa" {
  variable_set_id = tfe_variable_set.bootstrap_accounts_qa.id
  project_id      = tfe_project.bootstrap_qa.id
}

resource "tfe_variable" "vault_config_username_qa" {
  key            = "vault_config_username"
  value          = "core-aws"
  description    = "Username to authenticate to Vault."
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts_qa.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_config_password_qa" {
  key            = "vault_config_password"
  value          = "POPULATE IN UI"
  description    = "Password to authenticate to Vault."
  category       = "terraform"
  sensitive      = true
  variable_set_id = tfe_variable_set.bootstrap_accounts_qa.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_addr_qa" {
  key            = "vault_addr"
  value          = "https://vault-cc.qa.duke-energy.com"
  description    = "Vault address for QA"
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts_qa.id
}

################################################################################
# prod varset
################################################################################

resource "tfe_variable_set" "bootstrap_accounts_prod" {
  name         = "bootstrap-accounts-prod"
  description  = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for PROD accounts."
  organization = "core-aws"
}

resource "tfe_project_variable_set" "bootstrap_accounts_prod" {
  variable_set_id = tfe_variable_set.bootstrap_accounts_prod.id
  project_id      = tfe_project.bootstrap_prod.id
}

resource "tfe_project_variable_set" "bootstrap_accounts_workbench" {
  variable_set_id = tfe_variable_set.bootstrap_accounts_prod.id
  project_id      = tfe_project.bootstrap_workbench.id
}

resource "tfe_variable" "vault_config_username_prod" {
  key            = "vault_config_username"
  value          = "core-aws"
  description    = "Username to authenticate to Vault."
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts_prod.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_config_password_prod" {
  key            = "vault_config_password"
  value          = "POPULATE IN UI"
  description    = "Password to authenticate to Vault."
  category       = "terraform"
  sensitive      = true
  variable_set_id = tfe_variable_set.bootstrap_accounts_prod.id
  lifecycle {
    ignore_changes = [value]
  }
}

resource "tfe_variable" "vault_addr_prod" {
  key            = "vault_addr"
  value          = "https://vault-cc.prod.duke-energy.com"
  description    = "Vault address for PROD"
  category       = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_accounts_prod.id
}