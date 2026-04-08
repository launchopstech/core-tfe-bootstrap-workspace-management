locals {
  config      = var.iam_config_json
  name_prefix = "${var.client_id}-${var.environment}"

  oidc_cfg = try(local.config.oidc, {})
  oidc = {
    issuer_url      = try(trimspace(local.oidc_cfg.issuer_url), "")
    provider_arn    = try(trimspace(local.oidc_cfg.provider_arn), "")
    client_id_list  = distinct([for client_id in try(local.oidc_cfg.client_id_list, []) : trimspace(client_id) if trimspace(client_id) != ""])
    thumbprint_list = distinct([for thumbprint in try(local.oidc_cfg.thumbprint_list, []) : lower(trimspace(thumbprint)) if trimspace(thumbprint) != ""])
    roles = {
      for role_key, role in try(local.oidc_cfg.roles, {}) : role_key => {
        role_name_suffix    = try(trimspace(role.role_name_suffix), "")
        description         = try(role.description, null)
        managed_policy_arns = distinct([for arn in try(role.managed_policy_arns, []) : trimspace(arn) if trimspace(arn) != ""])
        inline_policy_json = (
          try(role.inline_policy_json, null) == null ? "" :
          can(trimspace(role.inline_policy_json)) ? trimspace(role.inline_policy_json) :
          jsonencode(role.inline_policy_json)
        )
        audience_values = distinct([for aud in try(role.audience_values, []) : trimspace(aud) if trimspace(aud) != ""])
        subject_claims  = distinct([for claim in try(role.subject_claims, []) : trimspace(claim) if trimspace(claim) != ""])
        tags            = try(role.tags, {})
      }
    }
  }

  role_name_suffixes = [
    for role_key, role in local.oidc.roles : role.role_name_suffix
    if role.role_name_suffix != ""
  ]
}

resource "terraform_data" "iam_config_validation" {
  input = local.config

  lifecycle {
    precondition {
      condition = alltrue([
        for role_key, role in local.oidc.roles :
        can(regex("^[A-Za-z0-9_.-]+$", role_key))
      ])
      error_message = "Each oidc.roles key must use a stable identifier containing only letters, digits, dot, underscore, or hyphen."
    }

    precondition {
      condition = alltrue([
        for role_key, role in local.oidc.roles :
        length(role.managed_policy_arns) > 0 || role.inline_policy_json != ""
      ])
      error_message = "Each oidc.roles entry requires at least one managed_policy_arn or a non-empty inline_policy_json."
    }

    precondition {
      condition = alltrue([
        for role_key, role in local.oidc.roles :
        role.inline_policy_json == "" || can(jsondecode(role.inline_policy_json))
      ])
      error_message = "Each oidc.roles inline_policy_json must be valid JSON when provided."
    }

    precondition {
      condition = alltrue([
        for role_key, role in local.oidc.roles :
        role.role_name_suffix == "" || can(regex("^[A-Za-z0-9+=,.@_/-]+$", role.role_name_suffix))
      ])
      error_message = "Each oidc.roles role_name_suffix must use IAM-safe characters only: letters, digits, +=,.@_/-."
    }

    precondition {
      condition     = length(distinct(local.role_name_suffixes)) == length(local.role_name_suffixes)
      error_message = "oidc.roles role_name_suffix values must be unique when provided."
    }

    precondition {
      condition = alltrue([
        for role_key, role in local.oidc.roles :
        length(role.subject_claims) > 0
      ])
      error_message = "Each oidc.roles entry requires at least one subject_claim."
    }

    precondition {
      condition     = local.oidc.provider_arn == "" || can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/.+$", local.oidc.provider_arn))
      error_message = "oidc.provider_arn must be a valid IAM OIDC provider ARN when provided."
    }

    precondition {
      condition     = length(local.oidc.roles) == 0 || can(regex("^https://.+$", local.oidc.issuer_url))
      error_message = "oidc.issuer_url is required and must be an https URL when oidc.roles are configured."
    }

    precondition {
      condition     = length(local.oidc.roles) == 0 || local.oidc.provider_arn != "" || (length(local.oidc.client_id_list) > 0 && length(local.oidc.thumbprint_list) > 0)
      error_message = "When oidc.roles are configured, provide either oidc.provider_arn or both oidc.client_id_list and oidc.thumbprint_list so this workspace can create the provider."
    }
  }
}

module "iam_access" {
  source = "../../modules/aws/iam-access"

  name_prefix          = local.name_prefix
  client_id            = var.client_id
  environment          = var.environment
  oidc_issuer_url      = local.oidc.issuer_url
  oidc_provider_arn    = local.oidc.provider_arn != "" ? local.oidc.provider_arn : null
  oidc_client_id_list  = local.oidc.client_id_list
  oidc_thumbprint_list = local.oidc.thumbprint_list
  oidc_roles           = local.oidc.roles
  tags                 = var.tags

  depends_on = [terraform_data.iam_config_validation]
}
