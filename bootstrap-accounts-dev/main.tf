terraform {
  cloud {
    hostname = "app.terraform.io"
    organization = "core-aws"
    workspaces {
      name = "bootstrap-account-workspace-management-dev"
    }
  }

  required_version = ">= 1.0"
  required_providers  {
    tfe = {
      version = "~> 0.49.0"
    }
    vault = {
      version = "~> 3.11.0"
    }
  }
}

# import {
#   id = module.workspaces.tfe_workspace.bootstrap_account["889851937279"]
#   to = "org-uZiJo51NjS4r5PGr"
# }