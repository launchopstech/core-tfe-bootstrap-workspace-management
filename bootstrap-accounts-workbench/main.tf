terraform {
  cloud {
    hostname = "app.terraform.io"
    workspaces {
      name = "bootstrap-account-workspace-management-workbench"
    }
  }

  required_version = ">= 1.2"
  required_providers {
    tfe = {
      version = "~> 0.49.0"
    }
  }
}
