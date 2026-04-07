terraform {
  required_version = ">= 1.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.49.0"
    }
  }
}
