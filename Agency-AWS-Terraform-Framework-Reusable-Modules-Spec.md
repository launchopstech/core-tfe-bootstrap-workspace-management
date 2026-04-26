# Refactor New API/Lambda Code Into Reusable Lego Modules

## Summary
- Refactor only the new code in this changeset: `modules/aws/api-gateway`, `modules/aws/lambda-function`, `modules/aws/rds-proxy`, `workspaces/api`, `workspaces/lambda`, and the new portal/bootstrap wiring for those roots.
- Make the workspace roots the JSON boundary. Introduce `api_config_json` and `lambda_config_json` as the only service-specific config inputs for the new roots, decode once in the workspace, and pass typed objects/maps into reusable modules.
- Keep the reusable modules generic. The API module must stop knowing about `crud`, `presign`, and `authorizer` by name; those become config-driven route/authorizer/integration definitions.
- Do not refactor older stable roots in this pass.
 
## Implementation Changes
- Replace the current flat input contract for `workspaces/api` with `api_config_json` and for `workspaces/lambda` with `lambda_config_json`.
  - Keep only metadata/dependency variables outside the blob: `client_id`, `environment`, `aws_region`, `hcp_terraform_organization`, and dependency workspace names.
  - Remove the new flat service variables instead of preserving them, since this code is still new and not yet the stable contract.

- Refactor `workspaces/api` into a composer/root that:
  - decodes `api_config_json` into a typed local object with sections for `gateway`, `lambdas`, `uploads`, and `database`
  - instantiates `lambda-function` modules with `for_each` over the lambda definitions
  - instantiates `rds-proxy` only when database/proxy config is enabled
  - instantiates `s3-secure` only when uploads are enabled
  - builds the generic API Gateway module from decoded `authorizers`, `routes`, `integrations`, `cors`, and `stage` config
  - generates Lambda environment maps in the workspace root, not inside the API module

- Refactor `workspaces/lambda` into a simpler composer/root that:
  - decodes `lambda_config_json`
  - passes typed `package`, `runtime`, `environment`, `network`, `logging`, and `iam` values into the generic lambda module
  - conditionally reads VPC outputs only when `network.enabled = true`

- Update control-plane and portal wiring for the new roots only.
  - `bootstrap-accounts` required inputs change to `api_config_json` and `lambda_config_json`
  - `workspaces/account-portal` required inputs change to the same single-blob fields
  - API default dependencies become `secure-baseline`, `vpc`, and `rds`
  - Lambda always depends on `secure-baseline`, and additionally depends on `vpc` when the decoded lambda config has `network.enabled = true`
  - Dependency workspace name injection remains derived from dependencies, so `secure_baseline_workspace_name`, `vpc_workspace_name`, and `rds_workspace_name` are populated automatically for the new roots

- Split modules by concern and keep them generic.
  - `modules/aws/api-gateway`: split into `rest_api.tf`, `authorizers.tf`, `routes.tf`, `cors.tf`, `logging.tf`, `deployment.tf`, `permissions.tf`, `variables.tf`, `outputs.tf`
  - `modules/aws/lambda-function`: split into `iam.tf`, `networking.tf`, `logging.tf`, `function.tf`, `variables.tf`, `outputs.tf`
  - `modules/aws/rds-proxy`: split into `iam.tf`, `networking.tf`, `proxy.tf`, `targets.tf`, `variables.tf`, `outputs.tf`

- Redesign `modules/aws/api-gateway` as a reusable contract.
  - Replace named inputs like `crud_lambda_*`, `authorizer_lambda_*`, and `presign_lambda_*`
  - New public interface accepts:
    - `authorizers = map(object(...))`
    - `integrations = map(object(...))`
    - `routes = list(object(...))`
    - `cors = object(...)`
    - `stage = object(...)`
    - `lambda_permissions = map(object(...))` or derived permissions for lambda-backed integrations/authorizers
  - Route config must support root paths as well as nested paths; do not assume `{proxy+}` only

- Keep `modules/aws/lambda-function` generic and typed.
  - Accept a typed package object, typed environment map, typed optional VPC object, logging config, and IAM policy inputs
  - Keep Lambda-specific infrastructure only: role, optional VPC SG, log group, function
  - Do not decode JSON inside the module

- Keep `modules/aws/rds-proxy` generic and typed.
  - Scope it to proxy IAM role, proxy SG, proxy resource, and target attachment only
  - Do not generate client Lambda IAM-auth policies inside this module
  - Add outputs needed by consumers, but keep app-specific policy construction in the workspace root

- Fix the DB/IAM contract for API composition.
  - Extend the RDS wrappers and `workspaces/rds` outputs to expose a unified `db_resource_id` and `db_username`
  - For single-instance RDS, surface the DB instance resource ID from the secure wrapper
  - For Aurora, surface the cluster resource ID from the Aurora wrapper
  - In `workspaces/api`, build the `rds-db:connect` IAM resource from `db_resource_id` plus `db_username`, not from the proxy ARN
  - This removes the current proxy/Lambda dependency cycle and uses the correct IAM-auth target identity

## Public Interface Changes
- `workspaces/api`
  - remove current service-specific variables
  - add `api_config_json : string`
- `workspaces/lambda`
  - remove current service-specific variables
  - add `lambda_config_json : string`
- `modules/aws/api-gateway`
  - replace named lambda inputs with generic `authorizers`, `integrations`, `routes`, `cors`, and `stage` inputs
- `workspaces/rds`
  - add unified outputs `db_resource_id` and `db_username`
- `bootstrap-accounts` and `workspaces/account-portal`
  - update required-input validation and seeded request generation to use `api_config_json` / `lambda_config_json`

## Test Plan
- Static/module validation
  - `terraform fmt -check` across the refactored new modules and roots
  - `terraform init -backend=false` and `terraform validate` for `modules/aws/api-gateway`, `modules/aws/lambda-function`, `modules/aws/rds-proxy`, `workspaces/api`, and `workspaces/lambda`

- Contract/config scenarios
  - API config with uploads enabled, authorizer enabled, CRUD lambda, presign lambda, proxy enabled
  - API config with uploads disabled and no presign route
  - Lambda config with `network.enabled = false`
  - Lambda config with `network.enabled = true`

- Wiring/dependency scenarios
  - Portal-created API workspace receives `secure_baseline_workspace_name`, `vpc_workspace_name`, and `rds_workspace_name`
  - Portal-created Lambda workspace receives `vpc_workspace_name` only when VPC networking is enabled
  - `auth_providers` and similar structured config values round-trip through control plane and portal without string/type mismatches

- Behavior/regression checks
  - API Gateway module can define both root and nested routes from config
  - CRUD Lambda IAM policy uses `db_resource_id` + `db_username`
  - No dependency cycle remains between proxy creation and Lambda IAM policy generation

## Assumptions
- The new API/Lambda roots are not yet a stable external contract, so replacing the new flat variables with `*_config_json` is acceptable in this refactor.
- The workspace root is the only place where JSON is decoded; reusable modules receive typed Terraform objects/maps only.
- API Gateway remains REST API v1 in this pass; no switch to HTTP API.
- Older stable roots and older module contracts stay untouched unless they must expose minimal new outputs (`db_resource_id`, `db_username`) to support the new API stack.
