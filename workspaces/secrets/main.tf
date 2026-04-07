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

  github_actions_cfg               = try(local.config.github_actions, {})
  github_actions_oidc_provider_arn = trimspace(try(local.github_actions_cfg.oidc_provider_arn, ""))
  github_actions_repositories = {
    for repo_key, repo in try(local.github_actions_cfg.repositories, {}) : repo_key => {
      aws_access = {
        mode                         = lower(trimspace(try(repo.aws_access.mode, "oidc_role")))
        role_name_suffix             = trimspace(try(repo.aws_access.role_name_suffix, ""))
        managed_policy_arns          = distinct([for arn in try(repo.aws_access.managed_policy_arns, []) : trimspace(arn) if trimspace(arn) != ""])
        inline_policy_json           = trimspace(try(repo.aws_access.inline_policy_json, ""))
        subject_claims               = distinct([for claim in try(repo.aws_access.subject_claims, []) : trimspace(claim) if trimspace(claim) != ""])
        access_key_id_secret_key     = trimspace(try(repo.aws_access.access_key_id_secret_key, ""))
        secret_access_key_secret_key = trimspace(try(repo.aws_access.secret_access_key_secret_key, ""))
      }
    }
  }

  github_actions_oidc_repositories = {
    for repo_key, repo in local.github_actions_repositories :
    repo_key => repo
    if repo.aws_access.mode == "oidc_role"
  }

  github_actions_static_key_repositories = {
    for repo_key, repo in local.github_actions_repositories :
    repo_key => repo
    if repo.aws_access.mode == "static_keys"
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

    precondition {
      condition = alltrue([
        for repo_key, repo in local.github_actions_repositories :
        can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", repo_key)) &&
        contains(["oidc_role", "static_keys"], repo.aws_access.mode)
      ])
      error_message = "Each github_actions.repositories key must be in owner/repo format, and aws_access.mode must be either oidc_role or static_keys."
    }

    precondition {
      condition = alltrue([
        for repo_key, repo in local.github_actions_oidc_repositories :
        length(repo.aws_access.managed_policy_arns) > 0 || repo.aws_access.inline_policy_json != ""
      ])
      error_message = "Each github_actions oidc_role entry requires at least one managed_policy_arn or a non-empty inline_policy_json."
    }

    precondition {
      condition = alltrue([
        for repo_key, repo in local.github_actions_oidc_repositories :
        repo.aws_access.inline_policy_json == "" || can(jsondecode(repo.aws_access.inline_policy_json))
      ])
      error_message = "Each github_actions oidc_role inline_policy_json must be valid JSON when provided."
    }

    precondition {
      condition = alltrue([
        for repo_key, repo in local.github_actions_static_key_repositories :
        repo.aws_access.access_key_id_secret_key != "" &&
        repo.aws_access.secret_access_key_secret_key != "" &&
        contains(keys(local.normalized_secrets), repo.aws_access.access_key_id_secret_key) &&
        contains(keys(local.normalized_secrets), repo.aws_access.secret_access_key_secret_key)
      ])
      error_message = "Each github_actions static_keys entry requires access_key_id_secret_key and secret_access_key_secret_key that reference keys in secrets_config_json.secrets."
    }

    precondition {
      condition     = local.github_actions_oidc_provider_arn == "" || can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/.+$", local.github_actions_oidc_provider_arn))
      error_message = "github_actions.oidc_provider_arn must be a valid IAM OIDC provider ARN when provided."
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
  github_actions = {
    oidc_provider_arn = local.github_actions_oidc_provider_arn != "" ? local.github_actions_oidc_provider_arn : null
    repositories      = local.github_actions_repositories
  }
  tags = var.tags

  depends_on = [terraform_data.secrets_config_validation]
}
