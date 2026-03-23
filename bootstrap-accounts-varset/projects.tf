resource "tfe_project" "bootstrap_sbx" {
  name         = "bootstrap-sbx"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_dev" {
  name         = "bootstrap-dev"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_qa" {
  name         = "bootstrap-qa"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_prod" {
  name         = "bootstrap-prod"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_workbench" {
  name         = "bootstrap-workbench"
  organization = "core-aws"
}

################################################################################
# Team projects (client-facing, one per environment)
################################################################################

resource "tfe_project" "team_sbx" {
  name         = "team-sbx"
  organization = "core-aws"
}

resource "tfe_project" "team_dev" {
  name         = "team-dev"
  organization = "core-aws"
}

resource "tfe_project" "team_qa" {
  name         = "team-qa"
  organization = "core-aws"
}

resource "tfe_project" "team_prod" {
  name         = "team-prod"
  organization = "core-aws"
}

resource "tfe_project" "team_workbench" {
  name         = "team-workbench"
  organization = "core-aws"
}
