# ── Contract validation ──────────────────────────────────────────────────────
resource "terraform_data" "api_config_validation" {
  input = local.config

  lifecycle {
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
  }
}
