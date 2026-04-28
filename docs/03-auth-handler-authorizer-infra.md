# 03 — Auth Handler & Authorizer Infrastructure

## Overview

`forge-core` ships two deployable units that need Terraform provisioning:

1. **auth-handler** (`apps/auth-handler/`) — An OIDC authorization server with its own Lambda + API Gateway. No authorizer on its routes — it IS the auth provider.
2. **authorizer** (`apps/authorizer/`) — A Lambda TOKEN authorizer wired into the main API Gateway. Validates platform JWTs before requests reach the API Lambda.

No module changes are needed. The existing `api-gateway`, `lambda-function`, and `secrets-manager` modules support everything required. Only workspace variable JSON needs updating.

---

## Deployment Architecture

```
Client / Frontend
      │
      ├─► https://auth.{domain}        ← auth-handler workspace
      │         API GW (no authorizer on any route)
      │         └── auth-handler Lambda
      │               secrets: ISSUER, AUDIENCE, PRIVATE_KEY, PUBLIC_KEY, COOKIE_SECRET, CONNECTIONS_JSON
      │               plain:   NODE_ENV, ALLOWED_ORG_IDS
      │
      └─► https://api.{domain}         ← api workspace
                API GW (TOKEN authorizer on all routes)
                ├── authorizer Lambda  ← invoked by API GW before every request
                │     secrets: ISSUER, AUDIENCE, PUBLIC_KEY
                └── api Lambda         ← reached only after Allow policy
```

---

## Step 1: Secrets Workspace

Add to `secrets_config_json` in the **secrets** TFE workspace:

```json
{
  "auth_handler_private_key": {
    "name_suffix": "auth-handler-private-key",
    "recovery_window_in_days": 7
  },
  "auth_handler_public_key": {
    "name_suffix": "auth-handler-public-key",
    "recovery_window_in_days": 7
  },
  "auth_handler_cookie_secret": {
    "name_suffix": "auth-handler-cookie-secret",
    "recovery_window_in_days": 7
  },
  "auth_handler_connections_json": {
    "name_suffix": "auth-handler-connections",
    "recovery_window_in_days": 7
  },
  "auth_handler_issuer": {
    "name_suffix": "auth-handler-issuer",
    "recovery_window_in_days": 7
  },
  "auth_handler_audience": {
    "name_suffix": "auth-handler-audience",
    "recovery_window_in_days": 7
  }
}
```

**After apply:** populate each secret with `aws secretsmanager put-secret-value` or CI/CD,
then set `version_exists = true` for each populated secret in `secrets_config_json`.
After that, note the six secret ARNs from `secret_arns` output. These are referenced by
`env_vars` keys in the Lambda configs below — Terraform injects ARNs as env var values,
and Lambda code calls `GetSecretValue` at runtime to resolve plaintext.

Do not apply the consuming `api` or `lambda` workspace until every referenced
secret has `version_exists = true`. Consumer workspaces read the sibling
`secrets_with_versions` output and intentionally fail fast if an `env_vars`
reference points at a secret container with no current version.

For a combined auth-handler + authorizer API workspace, these logical secret
keys must be ready before apply:

- `auth_handler_issuer`
- `auth_handler_audience`
- `auth_handler_private_key`
- `auth_handler_public_key`
- `auth_handler_cookie_secret`
- `auth_handler_connections_json`

**Generating production keys:**
```bash
# RS256 key pair
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem

# Cookie secret (32 random bytes, base64)
openssl rand -base64 32
```

---

## Step 2: Auth-Handler Workspace

Create a new TFE workspace using the `workspaces/api/` pattern.
Set `api_config_json` to:

```json
{
  "gateway": {
    "enabled": true,
    "stage": { "name": "v1" },
    "cors": {
      "allowed_origins": ["https://app.{domain}", "https://api.{domain}"]
    },
    "custom_domains": {
      "auth": {
        "domain_name": "auth.{domain}",
        "base_path": ""
      }
    },
    "routes": {
      "proxy": {
        "path_part": "{proxy+}",
        "methods": ["ANY"],
        "integration_key": "auth-handler"
      }
    }
  },
  "lambdas": {
    "auth-handler": {
      "function_name_suffix": "auth-handler",
      "handler": "auth-handler.handler",
      "runtime": "nodejs22.x",
      "memory_mb": 256,
      "timeout_seconds": 29,
      "needs_vpc": false,
      "needs_db": false,
      "env_vars": {
        "AUTH_HANDLER_ISSUER":               "auth_handler_issuer",
        "AUTH_HANDLER_AUDIENCE":             "auth_handler_audience",
        "AUTH_HANDLER_PRIVATE_KEY":          "auth_handler_private_key",
        "AUTH_HANDLER_PUBLIC_KEY":           "auth_handler_public_key",
        "AUTH_HANDLER_COOKIE_SECRET":        "auth_handler_cookie_secret",
        "AUTH_HANDLER_CONNECTIONS_JSON":     "auth_handler_connections_json"
      }
    }
  },
  "artifacts": {
    "key_prefix": "auth-handler"
  }
}
```

> No `authorizer_key` on the proxy route — auth-handler routes are public by design.

### Remaining plain env vars (set as TFE workspace variables)

| Variable | Value |
|----------|-------|
| `NODE_ENV` | `production` |
| `ALLOWED_ORG_IDS` | Comma-separated allowed org IDs |

---

## Step 3: API Workspace

Add the **authorizer Lambda** to the existing `api_config_json` and wire it into `gateway.authorizers`.

**Additions to `gateway`:**
```json
{
  "authorizers": {
    "token": {
      "lambda_key": "authorizer"
    }
  },
  "routes": {
    "proxy": {
      "path_part": "{proxy+}",
      "methods": ["ANY"],
      "integration_key": "api",
      "authorizer_key": "token"
    }
  }
}
```

**Addition to `lambdas`:**
```json
{
  "authorizer": {
    "function_name_suffix": "api-authorizer",
    "handler": "authorizer.handler",
    "runtime": "nodejs22.x",
    "memory_mb": 128,
    "timeout_seconds": 10,
    "needs_vpc": false,
    "needs_db": false,
    "env_vars": {
      "AUTH_HANDLER_ISSUER": "auth_handler_issuer",
      "AUTH_HANDLER_AUDIENCE": "auth_handler_audience",
      "AUTH_HANDLER_PUBLIC_KEY": "auth_handler_public_key"
    }
  }
}
```

> `AUTH_HANDLER_PUBLIC_KEY` is injected as a Secrets Manager ARN. The authorizer's
> `resolveSecret()` function detects ARN format and calls `GetSecretValue` at cold start.

## Step 4: IAM — handled automatically

The framework handles all IAM automatically:

- **Secrets access**: `workspaces/api/iam.tf` dynamically generates `secretsmanager:GetSecretValue`
  statements for every Lambda that has `env_vars` entries. No manual policy needed.
- **Authorizer invoke**: `modules/aws/api-gateway/authorizers.tf` creates a dedicated IAM role with
  `lambda:InvokeFunction` on the authorizer Lambda whenever `gateway.authorizers` is populated.
- **KMS decrypt**: Granted automatically if a `kms_key_arn` is available from the secure-baseline workspace.

---

## Step 5: CI/CD — artifact key alignment

The `forge-core` CI pipeline (`feat/cicd-pipeline` branch) uploads Lambda ZIPs to S3 with these keys:

| Lambda | S3 key |
|--------|--------|
| `apps/api` | `api/handler.zip` |
| `apps/auth-handler` | `auth-handler/handler.zip` |
| `apps/authorizer` | `authorizer/handler.zip` |

The `api_config_json.artifacts.key_prefix` in each workspace must match the corresponding S3 key prefix.

---

## Step 6: Post-Apply Checklist

After both workspaces have been applied:

| Action | Detail |
|--------|--------|
| Set issuer secret | Update `auth-handler-issuer` to the auth-handler custom domain URL |
| Set audience secret | Update `auth-handler-audience` to the expected JWT audience such as `forge-core-api` |
| Set real private key | Update `auth-handler-private-key` secret to the generated RSA private key PEM |
| Set real public key | Update `auth-handler-public-key` secret to the matching RSA public key PEM |
| Set cookie secret | Update `auth-handler-cookie-secret` to a random 32-byte base64 string |
| Set provider config | Update `auth-handler-connections` to the JSON array of upstream OIDC connection configs |
| Register callback URL | In Clerk OAuth app settings: `https://auth.{domain}/callback/clerk` |
| Frontend env | Point `NEXT_PUBLIC_AUTH_ISSUER` to `https://auth.{domain}` |

After the secret values are populated, update the matching
`secrets_config_json.secrets.<key>.version_exists` values to `true` and apply
the `secrets` workspace again. Only then apply the consuming `api` workspace.

If the API apply fails with `local.secrets_with_versions is empty` or
`One or more env_vars references point to a secret container with no current
version`, the consuming workspace is ahead of the secret readiness marker. Fix
the referenced secrets and re-apply `secrets` before re-running `api`.

---

## TFE Workspace Dependency Order

```
secure-baseline
      │
      ├── secrets  ← provision secrets first, get ARNs
      │
      ├── auth-handler  ← needs secrets ARNs + secure-baseline KMS
      │
      └── api  ← needs secrets ARNs, auth-handler ISSUER URL
```

---

---

## Step 7: Bootstrap Account JSON

The `services` list in `accounts.tf.json` is a set — it cannot hold duplicate entries. Auth-handler **cannot** be a second `api` entry. It must be registered as a new named service in the bootstrap layer.

### Changes to `bootstrap-accounts/locals.tf`

**Add to `_client_requestable_services`:**
```hcl
_client_requestable_services = toset([
  "vpc", "rds", "dns", "waf", "iam", "secrets", "lambda", "api",
  "auth-handler",   # ← new
])
```

**Add dependency requirements** (auth-handler needs KMS from secure-baseline and secret ARNs from secrets):
```hcl
service_dependency_requirements = {
  # ... existing entries ...
  "auth-handler" = toset(["secure-baseline", "secrets"])
}
```

**Add dependency workspace variable keys** (same pattern as `api`):
```hcl
service_dependency_workspace_variable_keys = {
  # ... existing entries ...
  "auth-handler" = {
    "secrets"          = "secrets_workspace_name"
    "secure-baseline"  = "secure_baseline_workspace_name"
    "dns"              = "dns_workspace_name"
  }
}
```

### Changes to `bootstrap-accounts/variables.tf` — `service_working_dirs`

```hcl
variable "service_working_dirs" {
  default = {
    # ... existing entries ...
    "auth-handler" = "workspaces/api"   # reuses workspaces/api/ Terraform codebase
  }
}
```

### Account JSON entry (`bootstrap-accounts-dev/accounts.tf.json`)

Add `"auth-handler"` to the `services` list and provide its config under `service_workspace_variables`:

```json
{
  "services": [
    "secure-baseline", "vpc", "rds", "dns", "waf",
    "iam", "secrets", "lambda", "api", "auth-handler"
  ],
  "service_workspace_variables": {
    "auth-handler": {
      "api_config_json": {
        "gateway": {
          "enabled": true,
          "stage": { "name": "v1" },
          "cors": {
            "allowed_origins": ["https://app.{domain}", "https://api.{domain}"]
          },
          "custom_domains": {
            "auth": { "domain_name": "auth.{domain}", "base_path": "" }
          },
          "routes": {
            "proxy": {
              "path_part": "{proxy+}",
              "methods": ["ANY"],
              "integration_key": "auth-handler"
            }
          }
        },
        "lambdas": {
          "auth-handler": {
            "function_name_suffix": "auth-handler",
            "handler": "auth-handler.handler",
            "runtime": "nodejs22.x",
            "memory_mb": 256,
            "timeout_seconds": 29,
            "env_vars": {
              "AUTH_HANDLER_ISSUER":               "auth_handler_issuer",
              "AUTH_HANDLER_AUDIENCE":             "auth_handler_audience",
              "AUTH_HANDLER_PRIVATE_KEY":          "auth_handler_private_key",
              "AUTH_HANDLER_PUBLIC_KEY":           "auth_handler_public_key",
              "AUTH_HANDLER_COOKIE_SECRET":        "auth_handler_cookie_secret",
              "AUTH_HANDLER_CONNECTIONS_JSON":     "auth_handler_connections_json"
            }
          }
        },
        "artifacts": { "key_prefix": "auth-handler" }
      }
    }
  }
}
```

> Keep secret-backed Lambda inputs under `env_vars`, backed by the sibling Secrets Manager workspace. Populate the secret values out-of-band, then set `version_exists = true` once each secret has a current version.

---

## Related

- `forge-core/docs/01-auth-handler-authorizer.md` — Implementation spec (endpoints, JWT claims, flows)
- `forge-core/docs/02-auth-provider-extensibility.md` — How to add OIDC providers via config
