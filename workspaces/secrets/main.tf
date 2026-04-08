locals {
  config      = var.secrets_config_json
  name_prefix = "${var.client_id}-${var.environment}"

  secrets_cfg = try(local.config.secrets, {})
  normalized_secrets = {
    for secret_key, secret in local.secrets_cfg : secret_key => {
      name_suffix             = trimspace(try(secret.name_suffix, ""))
      description             = try(secret.description, null)
      recovery_window_in_days = try(secret.recovery_window_in_days, 30)
      tags                    = try(secret.tags, {})
    }
  }

  secret_name_suffixes = [
    for secret_key, secret in local.normalized_secrets : secret.name_suffix
  ]

  kms_key_arn = nonsensitive(data.tfe_outputs.secure_baseline.values.kms_key_arn)
}

resource "terraform_data" "secrets_config_validation" {
  input = local.config

  lifecycle {
    precondition {
      condition = alltrue([
        for secret_key, secret in local.normalized_secrets :
        secret.name_suffix != "" &&
        can(regex("^[A-Za-z0-9/_+=.@-]+$", secret.name_suffix)) &&
        secret.recovery_window_in_days >= 7 &&
        secret.recovery_window_in_days <= 30
      ])
      error_message = "Each secrets_config_json.secrets entry requires a non-empty name_suffix using Secrets Manager-safe characters, and recovery_window_in_days between 7 and 30."
    }

    precondition {
      condition     = length(distinct(local.secret_name_suffixes)) == length(local.secret_name_suffixes)
      error_message = "secrets_config_json.secrets name_suffix values must be unique."
    }
  }
}

module "secrets" {
  source = "../../modules/aws/secrets-manager"

  name_prefix        = local.name_prefix
  client_id          = var.client_id
  environment        = var.environment
  kms_key_arn        = local.kms_key_arn
  secret_definitions = local.normalized_secrets
  tags               = var.tags

  depends_on = [terraform_data.secrets_config_validation]
}
