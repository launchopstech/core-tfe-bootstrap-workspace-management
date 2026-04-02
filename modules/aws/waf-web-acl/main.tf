resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = local.normalized_logging.retention_days
  tags              = local.base_tags
}

resource "aws_wafv2_ip_set" "this" {
  for_each = local.ip_sets

  name               = "${var.name}-${each.key}"
  description        = each.value.description
  scope              = var.scope
  ip_address_version = each.value.ip_address_version
  addresses          = each.value.addresses
  tags               = local.base_tags
}

resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = var.description
  scope       = var.scope
  tags        = local.base_tags

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }

    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups

    content {
      name     = rule.key
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name

          # This provider exposes rule_action_override rather than the older
          # excluded_rule block, so "excluded" subrules are neutralized by
          # overriding them to count instead of block.
          dynamic "rule_action_override" {
            for_each = rule.value.excluded_rules

            content {
              name = rule_action_override.value

              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = local.managed_rule_metric_names[rule.key]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.rate_rules

    content {
      name     = rule.key
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          aggregate_key_type = rule.value.aggregate_key_type
          limit              = rule.value.limit
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = local.rate_rule_metric_names[rule.key]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.ip_rules

    content {
      name     = rule.key
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.this[rule.value.ip_set_key].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = local.ip_rule_metric_names[rule.key]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.geo_rules

    content {
      name     = rule.key
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        geo_match_statement {
          country_codes = rule.value.country_codes
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = local.geo_rule_metric_names[rule.key]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.match_rules

    content {
      name     = rule.key
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        byte_match_statement {
          positional_constraint = rule.value.positional_constraint
          search_string         = rule.value.search_string

          field_to_match {
            dynamic "single_header" {
              for_each = rule.value.field_to_match.type == "single_header" ? [rule.value.field_to_match] : []

              content {
                name = single_header.value.name
              }
            }

            dynamic "single_query_argument" {
              for_each = rule.value.field_to_match.type == "single_query_argument" ? [rule.value.field_to_match] : []

              content {
                name = single_query_argument.value.name
              }
            }

            dynamic "body" {
              for_each = rule.value.field_to_match.type == "body" ? [rule.value.field_to_match] : []

              content {
                oversize_handling = body.value.oversize_handling
              }
            }

            dynamic "method" {
              for_each = rule.value.field_to_match.type == "method" ? [1] : []
              content {}
            }

            dynamic "query_string" {
              for_each = rule.value.field_to_match.type == "query_string" ? [1] : []
              content {}
            }

            dynamic "uri_path" {
              for_each = rule.value.field_to_match.type == "uri_path" ? [1] : []
              content {}
            }
          }

          dynamic "text_transformation" {
            for_each = rule.value.text_transformations

            content {
              priority = text_transformation.value.priority
              type     = text_transformation.value.type
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = local.match_rule_metric_names[rule.key]
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.acl_metric_name
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.this.arn]

  dynamic "redacted_fields" {
    for_each = local.normalized_logging.redacted_headers

    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }
}

resource "aws_wafv2_web_acl_association" "self" {
  count = local.self_attach ? 1 : 0

  resource_arn = local.normalized_attachment.resource_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
