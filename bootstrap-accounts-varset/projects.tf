resource "tfe_project" "bootstrap_sbx" {
  name         = "bootstrap-sbx"
  organization = var.organization
}

resource "tfe_project" "bootstrap_dev" {
  name         = "bootstrap-dev"
  organization = var.organization
}

resource "tfe_project" "bootstrap_qa" {
  name         = "bootstrap-qa"
  organization = var.organization
}

resource "tfe_project" "bootstrap_prod" {
  name         = "bootstrap-prod"
  organization = var.organization
}

resource "tfe_project" "bootstrap_workbench" {
  name         = "bootstrap-workbench"
  organization = var.organization
}

################################################################################
# Team projects (client-facing, one per environment)
################################################################################

resource "tfe_project" "team_sbx" {
  name         = "team-sbx"
  organization = var.organization
}

resource "tfe_project" "team_dev" {
  name         = "team-dev"
  organization = var.organization
}

resource "tfe_project" "team_qa" {
  name         = "team-qa"
  organization = var.organization
}

resource "tfe_project" "team_prod" {
  name         = "team-prod"
  organization = var.organization
}

resource "tfe_project" "team_workbench" {
  name         = "team-workbench"
  organization = var.organization
}
