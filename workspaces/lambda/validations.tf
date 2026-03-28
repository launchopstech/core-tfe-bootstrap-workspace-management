resource "terraform_data" "lambda_config_validation" {
  input = local.config

  lifecycle {
    precondition {
      condition     = local.resolved_s3_bucket != "" && local.configured_s3_key != ""
      error_message = "lambda_config_json.package.bucket and lambda_config_json.package.key are required."
    }

    precondition {
      condition     = !local.enable_vpc || trimspace(var.vpc_workspace_name) != ""
      error_message = "vpc_workspace_name is required when lambda_config_json.network.enabled = true."
    }
  }
}
