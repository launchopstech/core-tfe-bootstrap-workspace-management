terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "core-aws"
    workspaces {
      name = "bootstrap-account-workspace-management-workbench"
    }
  }

  required_version = ">= 1.0"
  required_providers {
    tfe = {
      version = "~> 0.49.0"
    }
  }
}
