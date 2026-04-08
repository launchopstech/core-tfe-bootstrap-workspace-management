provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      ClientId    = var.client_id
      Environment = var.environment
    }
  }
}
