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

    precondition {
      condition     = !local.has_secret_refs || trimspace(var.secrets_workspace_name) != ""
      error_message = "secrets_workspace_name is required when lambda_config_json.secret_refs is non-empty."
    }

    precondition {
      condition = alltrue([
        for env_name, secret_key in local.secret_refs :
        can(regex("^[A-Za-z_][A-Za-z0-9_]*$", env_name))
      ])
      error_message = "Each lambda_config_json.secret_refs key must be a valid environment-variable name."
    }

    precondition {
      condition     = length(local.missing_secret_keys) == 0
      error_message = "Each lambda_config_json.secret_refs value must reference a secret key published by the sibling secrets workspace."
    }
  }
}
