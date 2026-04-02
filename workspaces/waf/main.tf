locals {
  config       = var.waf_config_json
  name_prefix  = "${var.client_id}-${var.environment}"
  web_acl_name = "${local.name_prefix}-waf"

  default_action = lower(trimspace(try(local.config.default_action, "allow")))
  scope          = upper(trimspace(try(local.config.scope, "REGIONAL")))
  description    = try(local.config.description, null)

  attachment_cfg = try(local.config.attachment, {})
  attachment = {
    mode         = lower(trimspace(try(local.attachment_cfg.mode, "target")))
    resource_arn = trimspace(try(local.attachment_cfg.resource_arn, ""))
  }

  logging_cfg = try(local.config.logging, {})
  logging = {
    enabled          = try(local.logging_cfg.enabled, true)
    retention_days   = try(local.logging_cfg.retention_days, 30)
    redacted_headers = try(local.logging_cfg.redacted_headers, ["authorization"])
  }

  baseline_managed_rule_groups = {
    common = {
      priority        = 100
      vendor_name     = "AWS"
      name            = "AWSManagedRulesCommonRuleSet"
      override_action = "none"
      excluded_rules  = []
    }
    known_bad_inputs = {
      priority        = 110
      vendor_name     = "AWS"
      name            = "AWSManagedRulesKnownBadInputsRuleSet"
      override_action = "none"
      excluded_rules  = []
    }
    ip_reputation = {
      priority        = 120
      vendor_name     = "AWS"
      name            = "AWSManagedRulesAmazonIpReputationList"
      override_action = "none"
      excluded_rules  = []
    }
  }

  managed_rule_groups = length(try(local.config.managed_rule_groups, {})) > 0 ? try(local.config.managed_rule_groups, {}) : local.baseline_managed_rule_groups
  rate_rules          = try(local.config.rate_rules, {})
  ip_sets             = try(local.config.ip_sets, {})
  ip_rules            = try(local.config.ip_rules, {})
  geo_rules           = try(local.config.geo_rules, {})
  match_rules         = try(local.config.match_rules, {})

  all_rule_priorities = concat(
    [for key, rule in local.managed_rule_groups : rule.priority],
    [for key, rule in local.rate_rules : rule.priority],
    [for key, rule in local.ip_rules : rule.priority],
    [for key, rule in local.geo_rules : rule.priority],
    [for key, rule in local.match_rules : rule.priority],
  )

  supported_actions          = toset(["allow", "block", "count"])
  supported_override_actions = toset(["none", "count"])
  supported_ip_versions      = toset(["IPV4", "IPV6"])
  supported_match_fields     = toset(["single_header", "single_query_argument", "uri_path", "query_string", "method", "body"])
  supported_attachment_modes = toset(["target", "self"])
}

resource "terraform_data" "waf_config_validation" {
  input = local.config

  lifecycle {
    precondition {
      condition     = contains(["allow", "block"], local.default_action)
      error_message = "waf_config_json.default_action must be either \"allow\" or \"block\"."
    }

    precondition {
      condition     = local.scope == "REGIONAL"
      error_message = "waf_config_json.scope must be \"REGIONAL\" in v1."
    }

    precondition {
      condition     = local.logging.enabled
      error_message = "waf_config_json.logging.enabled cannot be false in v1. WAF logging is mandatory."
    }

    precondition {
      condition     = local.logging.retention_days > 0
      error_message = "waf_config_json.logging.retention_days must be a positive number of days."
    }

    precondition {
      condition     = contains(local.supported_attachment_modes, local.attachment.mode)
      error_message = "waf_config_json.attachment.mode must be either \"target\" or \"self\"."
    }

    precondition {
      condition     = local.attachment.mode != "self" || local.attachment.resource_arn != ""
      error_message = "waf_config_json.attachment.resource_arn is required when attachment.mode = \"self\"."
    }

    precondition {
      condition     = length(distinct(local.all_rule_priorities)) == length(local.all_rule_priorities)
      error_message = "All WAF rule priorities must be unique across managed_rule_groups, rate_rules, ip_rules, geo_rules, and match_rules."
    }

    precondition {
      condition = alltrue([
        for key, rule in local.managed_rule_groups :
        contains(local.supported_override_actions, lower(trimspace(try(rule.override_action, "none"))))
      ])
      error_message = "managed_rule_groups override_action must be either \"none\" or \"count\"."
    }

    precondition {
      condition = alltrue([
        for key, rule in local.rate_rules :
        upper(trimspace(try(rule.aggregate_key_type, "IP"))) == "IP" &&
        contains(local.supported_actions, lower(trimspace(try(rule.action, "block"))))
      ])
      error_message = "rate_rules currently support only aggregate_key_type = \"IP\", and action must be allow, block, or count."
    }

    precondition {
      condition = alltrue([
        for key, ip_set in local.ip_sets :
        contains(local.supported_ip_versions, upper(trimspace(try(ip_set.ip_address_version, "IPV4"))))
      ])
      error_message = "ip_sets ip_address_version must be either \"IPV4\" or \"IPV6\"."
    }

    precondition {
      condition = alltrue([
        for key, rule in local.ip_rules :
        contains(keys(local.ip_sets), trimspace(rule.ip_set_key)) &&
        contains(local.supported_actions, lower(trimspace(try(rule.action, "block"))))
      ])
      error_message = "Each ip_rules entry must reference an existing ip_sets key, and action must be allow, block, or count."
    }

    precondition {
      condition = alltrue([
        for key, rule in local.geo_rules :
        length(try(rule.country_codes, [])) > 0 &&
        contains(local.supported_actions, lower(trimspace(try(rule.action, "block"))))
      ])
      error_message = "Each geo_rules entry must include one or more country_codes, and action must be allow, block, or count."
    }

    precondition {
      condition = alltrue([
        for key, rule in local.match_rules :
        trimspace(try(rule.search_string, "")) != "" &&
        contains(local.supported_actions, lower(trimspace(try(rule.action, "block")))) &&
        contains(local.supported_match_fields, lower(trimspace(try(rule.field_to_match.type, "")))) &&
        (
          !contains(["single_header", "single_query_argument"], lower(trimspace(try(rule.field_to_match.type, "")))) ||
          trimspace(try(rule.field_to_match.name, "")) != ""
        )
      ])
      error_message = "Each match_rules entry requires search_string, a supported action, a supported field_to_match.type, and field_to_match.name for single_header or single_query_argument."
    }
  }
}

module "web_acl" {
  source = "../../modules/aws/waf-web-acl"

  name           = local.web_acl_name
  client_id      = var.client_id
  environment    = var.environment
  description    = local.description
  scope          = local.scope
  default_action = local.default_action
  attachment     = local.attachment
  logging = {
    retention_days   = local.logging.retention_days
    redacted_headers = local.logging.redacted_headers
  }
  managed_rule_groups = local.managed_rule_groups
  rate_rules          = local.rate_rules
  ip_sets             = local.ip_sets
  ip_rules            = local.ip_rules
  geo_rules           = local.geo_rules
  match_rules         = local.match_rules
  tags                = var.tags

  depends_on = [terraform_data.waf_config_validation]
}
