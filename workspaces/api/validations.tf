# ── Contract validation ──────────────────────────────────────────────────────
resource "terraform_data" "api_config_validation" {
  input = local.config

  lifecycle {
    precondition {
      condition     = !local.has_lambdas || (local.resolved_artifacts_bucket != "" && local.configured_artifacts_key_prefix != "" && local.configured_artifacts_version != "")
      error_message = "API lambdas require artifacts.bucket, artifacts.key_prefix, and artifacts.version."
    }

    # DB Lambdas require the proxy to be enabled
    precondition {
      condition = alltrue([
        for k, v in local.lambdas : !try(v.needs_db, false) || local.proxy_enabled
      ])
      error_message = "Lambda with needs_db = true requires database.proxy_enabled = true in api_config_json."
    }

    precondition {
      condition = alltrue([
        for k, v in local.lambdas : !try(v.needs_db, false) || local.db_iam_username != ""
      ])
      error_message = "Lambda with needs_db = true requires database.iam_username in api_config_json. Set it to an existing IAM-authenticated database role."
    }

    # VPC workspace name must be provided when VPC-attached resources exist
    precondition {
      condition     = !local.needs_vpc || var.vpc_workspace_name != null
      error_message = "vpc_workspace_name is required when any lambda needs VPC or DB access, or when RDS proxy is enabled."
    }

    # RDS workspace name must be provided when DB resources exist
    precondition {
      condition     = !local.needs_rds || var.rds_workspace_name != null
      error_message = "rds_workspace_name is required when any lambda needs DB access or when RDS proxy is enabled."
    }

    # CORS must have exactly one origin for static REST API implementation
    precondition {
      condition     = !local.gateway_enabled || length(try(local.gw.cors.allowed_origins, ["*"])) == 1
      error_message = "gateway.cors.allowed_origins requires exactly one origin for this REST API blueprint. Use a single origin or [\"*\"]."
    }

    precondition {
      condition     = local.gateway_enabled || length(local.custom_domains) == 0
      error_message = "gateway.custom_domains can only be used when gateway.enabled = true."
    }

    precondition {
      condition     = !local.custom_domains_need_dns || (var.dns_workspace_name != null && trimspace(var.dns_workspace_name) != "")
      error_message = "gateway.custom_domains entries without hosted_zone_id require dns_workspace_name so the hosted zone can be read from a sibling dns workspace."
    }

    precondition {
      condition = alltrue([
        for key, domain in local.resolved_custom_domains :
        trimspace(domain.domain_name) != "" &&
        can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$", trimspace(domain.domain_name))) &&
        trimspace(domain.hosted_zone_id) != "" &&
        can(regex("^Z[A-Z0-9]+$", upper(trimspace(domain.hosted_zone_id))))
      ])
      error_message = "Each gateway.custom_domains entry requires a valid domain_name and a usable same-account Route53 hosted zone ID, either set directly or read from dns_workspace_name."
    }

    precondition {
      condition     = length(distinct(local.normalized_custom_domain_names)) == length(local.normalized_custom_domain_names)
      error_message = "gateway.custom_domains domain_name values must be unique."
    }

    precondition {
      condition = alltrue([
        for key, domain in local.custom_domains :
        !startswith(trimspace(try(domain.base_path, "")), "/") &&
        !endswith(trimspace(try(domain.base_path, "")), "/")
      ])
      error_message = "gateway.custom_domains base_path must omit leading and trailing slashes. Use an empty string for root mapping or a value like \"api\"."
    }
  }
}
