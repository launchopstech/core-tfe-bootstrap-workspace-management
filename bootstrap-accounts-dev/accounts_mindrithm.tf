# ── Mindrithm account entry ──────────────────────────────────────────────────
# Defined in HCL so locals (account_id, product, env, region, kms_key_arn)
# can be referenced directly. Merged with accounts_static → accounts.
#
# NOTE: *_config_json values are kept as plain objects — the bootstrap module
# calls jsonencode() on each service_workspace_variable value before writing
# it as a tfe_variable, and also traverses these objects at plan time.
locals {
  accounts_mindrithm = {
    "mindrithm-dev" = {
      account_id                  = local.account_id
      client_id                   = local.product
      account_name                = "${local.product}.${local.env}"
      env                         = local.env
      product_name                = "platform"
      region                      = local.region
      security_tier               = "standard"
      enable_aws_preflight        = false
      workspace_env_suffix_mode   = true
      vcs_repo_identifier         = "launchopstech/core-tfe-bootstrap-workspace-management"
      service_vcs_repo_identifier = "launchopstech/core-tfe-bootstrap-workspace-management"
      working_directory           = "workspaces/account-bootstrap"
      services = [
        "account-bootstrap",
        "secure-baseline",
        "vpc",
        "rds",
        "secrets",
        "api",
      ]
      service_workspace_variables = {
        vpc = {
          cidr_block       = "10.1.0.0/16"
          azs              = ["us-east-1a", "us-east-1b"]
          private_subnets  = ["10.1.1.0/24", "10.1.2.0/24"]
          public_subnets   = ["10.1.101.0/24", "10.1.102.0/24"]
          database_subnets = ["10.1.201.0/24", "10.1.202.0/24"]
        }
        "secure-baseline" = {
          kms_key_arn            = local.kms_key_arn
          enable_config          = false
          enable_guardduty       = false
          enable_security_hub    = false
          enable_access_analyzer = false
          force_destroy          = true
        }
        rds = {
          kms_key_arn                 = local.kms_key_arn
          instance_class              = "db.t4g.small"
          db_name                     = "forge_agents"
          allocated_storage           = 20
          max_allocated_storage       = 0
          backup_retention_days       = 7
          deletion_protection         = false
          enable_performance_insights = false
          enable_enhanced_monitoring  = false
        }
        secrets = {
          secrets_config_json = {
            secrets = {
              auth_handler_issuer = {
                description             = "OIDC issuer URL for platform JWTs (AUTH_HANDLER_ISSUER)"
                recovery_window_in_days = 7
                version_exists          = false
              }
              auth_handler_audience = {
                description             = "JWT audience for platform tokens (AUTH_HANDLER_AUDIENCE)"
                recovery_window_in_days = 7
                version_exists          = false
              }
              auth_handler_private_key = {
                description             = "RS256 private key used by auth-handler to sign platform JWTs"
                recovery_window_in_days = 7
                version_exists          = false
              }
              auth_handler_public_key = {
                description             = "RS256 public key used by the Lambda authorizer to verify platform JWTs"
                recovery_window_in_days = 7
                version_exists          = false
              }
              auth_handler_cookie_secret = {
                description             = "AES cookie encryption secret for auth-handler browser sessions"
                recovery_window_in_days = 7
                version_exists          = false
              }
              auth_handler_connections_json = {
                description             = "JSON array of upstream OIDC connection configs (AUTH_HANDLER_CONNECTIONS_JSON)"
                recovery_window_in_days = 7
                version_exists          = false
              }
              anthropic_api_key = {
                description             = "Anthropic API key for forge-core-ai LLM calls"
                recovery_window_in_days = 7
                version_exists          = false
              }
            }
          }
        }
        api = {
          env_suffix_mode = true
          api_config_json = {
            gateway = {
              enabled = true
              cors = {
                allowed_origins = ["https://mindrithm.ai"]
              }
              stage = {
                name = "v1"
              }
              waf = {
                enabled = false
              }
              authorizers = {
                token = {
                  lambda_key = "authorizer"
                }
              }
              routes = {
                proxy = {
                  path_part       = "{proxy+}"
                  methods         = ["ANY"]
                  integration_key = "forge-core-api"
                  authorizer_key  = "token"
                }
                auth_proxy = {
                  path_part       = "auth"
                  methods         = ["ANY"]
                  integration_key = "auth-handler"
                  proxy_child     = true
                }
              }
            }
            lambdas = {
              "forge-core-api" = {
                name                 = "core-api"
                seed                 = "seed_handler"
                upload_seed_code     = true
                function_name_suffix = "core-api"
                handler              = "seed_handler.handler"
                runtime              = "python3.12"
                memory_mb            = 512
                timeout_seconds      = 30
                needs_vpc            = true
                needs_db             = true
                needs_uploads        = false
              }
              authorizer = {
                seed                 = "seed_authorizer"
                upload_seed_code     = false
                function_name_suffix = "api-authorizer"
                handler              = "authorizer.handler"
                runtime              = "nodejs22.x"
                memory_mb            = 128
                timeout_seconds      = 10
                needs_vpc            = false
                needs_db             = false
                needs_uploads        = false
                env_vars = {
                  AUTH_HANDLER_ISSUER     = "auth_handler_issuer"
                  AUTH_HANDLER_AUDIENCE   = "auth_handler_audience"
                  AUTH_HANDLER_PUBLIC_KEY = "auth_handler_public_key"
                }
              }
              "auth-handler" = {
                seed                 = "seed_auth_handler"
                upload_seed_code     = false
                function_name_suffix = "auth-handler"
                handler              = "auth-handler.handler"
                runtime              = "nodejs22.x"
                memory_mb            = 256
                timeout_seconds      = 29
                needs_vpc            = false
                needs_db             = false
                needs_uploads        = false
                env_vars = {
                  AUTH_HANDLER_ISSUER           = "auth_handler_issuer"
                  AUTH_HANDLER_AUDIENCE         = "auth_handler_audience"
                  AUTH_HANDLER_PRIVATE_KEY      = "auth_handler_private_key"
                  AUTH_HANDLER_PUBLIC_KEY       = "auth_handler_public_key"
                  AUTH_HANDLER_COOKIE_SECRET    = "auth_handler_cookie_secret"
                  AUTH_HANDLER_CONNECTIONS_JSON = "auth_handler_connections_json"
                }
              }
            }
            artifacts = {
              bucket           = "${local.product}-${local.env}-forge-api-code"
              create_bucket    = true
              key_prefix       = "api"
              upload_seed_code = false
              version          = "v0.1.0"
            }
            database = {
              proxy_enabled = true
              iam_username  = "app"
            }
            uploads = {
              enabled = false
            }
          }
        }
      }
    }
  }

  accounts = merge(local.accounts_static, local.accounts_mindrithm)
}
