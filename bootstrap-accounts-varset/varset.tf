################################################################################
# bootstrap-accounts-varset
################################################################################

resource "tfe_variable_set" "bootstrap_global" {
  name         = "bootstrap-accounts-global"
  description  = "WRITTEN BY AUTOMATION: Shared defaults used by all bootstrap-account workspaces."
  organization = "core-aws"
}

resource "tfe_variable" "bootstrap_global_managed_by" {
  key             = "managed_by"
  value           = "terraform"
  description     = "WRITTEN BY AUTOMATION: Declares the bootstrap control plane owner."
  category        = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_global.id
}

resource "tfe_variable" "bootstrap_global_workspace_class" {
  key             = "workspace_class"
  value           = "bootstrap-account"
  description     = "WRITTEN BY AUTOMATION: Shared workspace class for bootstrap-account workspaces."
  category        = "terraform"
  variable_set_id = tfe_variable_set.bootstrap_global.id
}

resource "tfe_variable_set" "bootstrap_environment" {
  for_each = local.environment_variable_sets

  name         = each.value.name
  description  = each.value.description
  organization = "core-aws"
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
  organization = "core-aws"
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
  organization = "core-aws"
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
