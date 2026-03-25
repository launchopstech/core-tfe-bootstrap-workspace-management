terraform {
  cloud {
    hostname = "app.terraform.io"

    workspaces {
      name = "00-bootstrap-account-workspace-management"
    }
  }

  required_version = ">= 1.0"
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.49.0"
    }
  }
}
