terraform {
  required_version = ">= 1.0"
  required_providers  {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.49.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.11.0"
    }
  }
}