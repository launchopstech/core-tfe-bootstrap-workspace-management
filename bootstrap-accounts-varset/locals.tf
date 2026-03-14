locals {
  environment_variable_sets = {
    sbx = {
      name        = "bootstrap-accounts-sbx"
      description = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for SBX accounts."
    }
    dev = {
      name        = "bootstrap-accounts-dev"
      description = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for DEV accounts."
    }
    qa = {
      name        = "bootstrap-accounts-qa"
      description = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for QA accounts."
    }
    prod = {
      name        = "bootstrap-accounts-prod"
      description = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for PROD accounts."
    }
    workbench = {
      name        = "bootstrap-accounts-workbench"
      description = "WRITTEN BY AUTOMATION: Shared variables used by bootstrap-account workspaces for WORKBENCH accounts."
    }
  }

  security_tier_variable_sets = {
    standard = {
      name        = "bootstrap-accounts-standard"
      description = "WRITTEN BY AUTOMATION: Shared variables used by standard-security bootstrap-account workspaces."
    }
    high = {
      name        = "bootstrap-accounts-high"
      description = "WRITTEN BY AUTOMATION: Shared variables used by high-security bootstrap-account workspaces."
    }
  }
}
