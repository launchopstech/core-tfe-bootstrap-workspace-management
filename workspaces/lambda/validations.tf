resource "terraform_data" "lambda_config_validation" {
  input = local.config

  lifecycle {
    precondition {
      condition     = !can(local.config.secret_refs)
      error_message = "lambda_config_json.secret_refs has been renamed to env_vars. Update your configuration."
    }

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
      error_message = "secrets_workspace_name is required when lambda_config_json.env_vars is non-empty."
    }

    precondition {
      condition = alltrue([
        for env_name, secret_key in local.secret_refs :
        can(regex("^[A-Za-z_][A-Za-z0-9_]*$", env_name))
      ])
      error_message = "Each lambda_config_json.env_vars key must be a valid environment-variable name."
    }

    precondition {
      condition     = length(local.missing_secret_keys) == 0
      error_message = "Each lambda_config_json.env_vars value must reference a secret key published by the sibling secrets workspace."
    }

    precondition {
      condition = alltrue([
        for env_name, secret_key in local.secret_refs :
        contains(tolist(local.secrets_with_versions), secret_key)
      ])
      error_message = "One or more env_vars references point to a secret container with no current version. Populate the secret out-of-band with 'aws secretsmanager put-secret-value' or CI/CD, then set version_exists = true in secrets_config_json."
    }
  }
}
