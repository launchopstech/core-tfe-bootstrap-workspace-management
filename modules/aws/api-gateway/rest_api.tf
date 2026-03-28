resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = "API for ${var.client_id} ${var.environment}."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.base_tags
}
