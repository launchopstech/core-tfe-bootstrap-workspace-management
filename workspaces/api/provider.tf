provider "aws" {
  region = var.aws_region

  # Authentication via HCP Terraform Dynamic Provider Credentials (OIDC).
  # Set TFC_AWS_PROVIDER_AUTH=true and TFC_AWS_RUN_ROLE_ARN on the workspace.

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      ClientId    = var.client_id
      Environment = var.environment
    }
  }
}
