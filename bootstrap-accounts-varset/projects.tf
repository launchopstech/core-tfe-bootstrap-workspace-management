resource "tfe_project" "bootstrap_sbx" {
  name        = "bootstrap-sbx"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_dev" {
  name        = "bootstrap-dev"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_qa" {
  name        = "bootstrap-qa"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_prod" {
  name        = "bootstrap-prod"
  organization = "core-aws"
}

resource "tfe_project" "bootstrap_workbench" {
  name        = "bootstrap-workbench"
  organization = "core-aws"
}