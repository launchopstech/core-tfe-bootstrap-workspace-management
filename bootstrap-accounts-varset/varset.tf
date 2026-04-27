################################################################################
# bootstrap-accounts-varset
################################################################################

resource "tfe_variable_set" "bootstrap_global" {
  name         = "bootstrap-accounts-global"
  description  = "WRITTEN BY AUTOMATION: Shared defaults used by all bootstrap-account workspaces."
  organization = var.organization
}

resource "tfe_variable_set" "bootstrap_environment" {
  for_each = local.environment_variable_sets

  name         = each.value.name
  description  = each.value.description
  organization = var.organization
}

resource "tfe_variable" "bootstrap_environment_name" {
  for_each = local.environment_variable_sets

  key             = "environment"
  value           = each.key
  description     = "WRITTEN BY AUTOMATION: Environment assigned to this bootstrap-account variable set."
  category        = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_environment[each.key].id
}

resource "tfe_variable_set" "bootstrap_security_tier" {
  for_each = local.security_tier_variable_sets

  name         = each.value.name
  description  = each.value.description
  organization = var.organization
}

resource "tfe_variable" "bootstrap_security_tier_name" {
  for_each = local.security_tier_variable_sets

  key             = "security_tier"
  value           = each.key
  description     = "WRITTEN BY AUTOMATION: Security tier assigned to this bootstrap-account variable set."
  category        = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_security_tier[each.key].id
}

resource "tfe_variable_set" "control_plane_secrets" {
  count = length(var.control_plane_sensitive_variables) > 0 ? 1 : 0

  name         = "bootstrap-accounts-control-plane-secrets"
  description  = "WRITTEN BY AUTOMATION: Shared sensitive values used by bootstrap-account workspaces."
  organization = var.organization
}

resource "tfe_variable" "control_plane_secrets" {
  for_each = toset(keys(nonsensitive(var.control_plane_sensitive_variables)))

  key             = each.value
  value           = var.control_plane_sensitive_variables[each.value]
  description     = "WRITTEN BY AUTOMATION: Shared control-plane sensitive value."
  category        = "terraform"
  sensitive       = true
  variable_set_id = tfe_variable_set.control_plane_secrets[0].id
}

################################################################################
# Portal automation token variable set
# Injected into all team-* projects so every account-portal workspace
# automatically receives TFE_TOKEN without manual configuration.
################################################################################

resource "tfe_variable_set" "portal_automation" {
  count = var.portal_automation_enabled ? 1 : 0

  name         = "portal-automation-token"
  description  = "WRITTEN BY AUTOMATION: TFE_TOKEN injected into all team-* projects so account-portal workspaces can create child deployer workspaces."
  organization = var.organization
}

resource "tfe_variable" "portal_tfe_token" {
  count = var.portal_automation_enabled ? 1 : 0

  key             = "TFE_TOKEN"
  value           = var.portal_automation_token
  description     = "WRITTEN BY AUTOMATION: Token used by account-portal workspaces to create and configure child deployer workspaces in HCP Terraform."
  category        = "env"
  sensitive       = true
  variable_set_id = tfe_variable_set.portal_automation[0].id
}

resource "tfe_project_variable_set" "portal_automation" {
  for_each = var.portal_automation_enabled ? {
    sbx       = tfe_project.team_sbx.id
    dev       = tfe_project.team_dev.id
    qa        = tfe_project.team_qa.id
    prod      = tfe_project.team_prod.id
    workbench = tfe_project.team_workbench.id
  } : {}

  project_id      = each.value
  variable_set_id = tfe_variable_set.portal_automation[0].id
}
