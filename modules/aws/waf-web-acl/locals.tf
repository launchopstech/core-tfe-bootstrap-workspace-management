locals {
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })

  normalized_attachment = {
    mode         = lower(trimspace(var.attachment.mode))
    resource_arn = trimspace(coalesce(try(var.attachment.resource_arn, null), ""))
  }

  normalized_logging = {
    retention_days = var.logging.retention_days
    redacted_headers = distinct([
      for header in var.logging.redacted_headers : lower(trimspace(header))
      if trimspace(header) != ""
    ])
  }

  managed_rule_groups = {
    for key, rule in var.managed_rule_groups : key => {
      priority        = rule.priority
      vendor_name     = trimspace(rule.vendor_name)
      name            = trimspace(rule.name)
      override_action = lower(trimspace(try(rule.override_action, "none")))
      excluded_rules = distinct([
        for excluded_rule in try(rule.excluded_rules, []) : trimspace(excluded_rule)
        if trimspace(excluded_rule) != ""
      ])
    }
  }

  rate_rules = {
    for key, rule in var.rate_rules : key => {
      priority           = rule.priority
      limit              = rule.limit
      aggregate_key_type = upper(trimspace(try(rule.aggregate_key_type, "IP")))
      action             = lower(trimspace(try(rule.action, "block")))
    }
  }

  ip_sets = {
    for key, ip_set in var.ip_sets : key => {
      addresses = distinct([
        for address in ip_set.addresses : trimspace(address)
        if trimspace(address) != ""
      ])
      ip_address_version = upper(trimspace(try(ip_set.ip_address_version, "IPV4")))
      description        = try(ip_set.description, null)
    }
  }

  ip_rules = {
    for key, rule in var.ip_rules : key => {
      priority   = rule.priority
      ip_set_key = trimspace(rule.ip_set_key)
      action     = lower(trimspace(try(rule.action, "block")))
    }
  }

  geo_rules = {
    for key, rule in var.geo_rules : key => {
      priority      = rule.priority
      country_codes = distinct([for code in rule.country_codes : upper(trimspace(code)) if trimspace(code) != ""])
      action        = lower(trimspace(try(rule.action, "block")))
    }
  }

  match_rules = {
    for key, rule in var.match_rules : key => {
      priority              = rule.priority
      action                = lower(trimspace(try(rule.action, "block")))
      search_string         = rule.search_string
      positional_constraint = upper(trimspace(try(rule.positional_constraint, "CONTAINS")))
      field_to_match = {
        type              = lower(trimspace(rule.field_to_match.type))
        name              = trimspace(coalesce(try(rule.field_to_match.name, null), ""))
        oversize_handling = upper(trimspace(try(rule.field_to_match.oversize_handling, "CONTINUE")))
      }
      text_transformations = [
        for transformation in try(rule.text_transformations, [{ priority = 0, type = "NONE" }]) : {
          priority = transformation.priority
          type     = upper(trimspace(transformation.type))
        }
      ]
    }
  }

  log_group_name = "aws-waf-logs-${var.name}"

  acl_metric_name = substr(replace(var.name, "/[^A-Za-z0-9_-]/", "-"), 0, 128)

  managed_rule_metric_names = {
    for key, rule in local.managed_rule_groups :
    key => substr(replace("${var.name}-${key}", "/[^A-Za-z0-9_-]/", "-"), 0, 128)
  }

  rate_rule_metric_names = {
    for key, rule in local.rate_rules :
    key => substr(replace("${var.name}-${key}", "/[^A-Za-z0-9_-]/", "-"), 0, 128)
  }

  ip_rule_metric_names = {
    for key, rule in local.ip_rules :
    key => substr(replace("${var.name}-${key}", "/[^A-Za-z0-9_-]/", "-"), 0, 128)
  }

  geo_rule_metric_names = {
    for key, rule in local.geo_rules :
    key => substr(replace("${var.name}-${key}", "/[^A-Za-z0-9_-]/", "-"), 0, 128)
  }

  match_rule_metric_names = {
    for key, rule in local.match_rules :
    key => substr(replace("${var.name}-${key}", "/[^A-Za-z0-9_-]/", "-"), 0, 128)
  }

  self_attach = local.normalized_attachment.mode == "self"
}
