# Agency Orchestration Platform Spec

Canonical architecture and roadmap for turning this repo into a fast HCP Terraform-centric orchestration product that captures the best early-value patterns from Spacelift, env0, and Atmos without overbuilding phase 1.

## Summary

This repository is the **agency control plane**.

It now owns:

- metadata-driven account onboarding through `accounts.tf.json`
- hidden bootstrap and preflight workspaces for agency-owned AWS access checks
- account portal workspaces keyed by `client_id` + `env`
- seeded project requests through `project_requests_json`
- agency-managed baseline deployers and client-facing child deployer workspaces
- shared variable-set inheritance, metadata persistence, notifications, and HCP Terraform OIDC wiring

The design direction is:

- `env0` and `Atmos` for blueprints, reusable stacks, and self-service
- `Spacelift` and `env0` for approvals, RBAC, policy hooks, and drift operations
- `Spacelift` and `Atmos` for dependency-aware orchestration

The active target is **HCP Terraform first**, Terraform/OpenTofu only, with no repo split required before MVP.

## Current State

Already implemented in this repo:

- [x] HCP Terraform control-plane bootstrap (`hcp-bootstrap/`)
- [x] environment-specific control-plane roots (`bootstrap-accounts-dev/`, `bootstrap-accounts-workbench/`)
- [x] project and variable-set factory (`bootstrap-accounts-varset/`)
- [x] metadata-driven onboarding with `accounts.tf.json`
- [x] Terraform `precondition` validation on account metadata
- [x] workspace metadata persistence through `tfe_variable`
- [x] HCP Terraform OIDC env injection for AWS-running workspaces
- [x] email failure notifications for control-plane workspaces
- [x] runtime roots for `account-bootstrap`, `secure-baseline`, `vpc`, and `rds`
- [x] account portal root at `workspaces/account-portal`
- [x] account portal naming keyed by `client_id` + `env`
- [x] account-portal seeding through `project_requests_json`
- [x] basic client-admin team access for the account portal and portal-created child deployer workspaces

Historical, no longer the active target:

- the old `catalog/` YAML/render pipeline
- a monolithic per-environment stack model
- keying visible workspaces directly by AWS account ID

## Public Interfaces

### `accounts.tf.json`

`accounts.tf.json` remains the only onboarding contract.

Required core fields:

- `account_id`
- `client_id` or `product_name`
- `env`
- `security_tier`
- `vcs_repo_identifier`

Supported orchestration fields:

- `services`
- `service_workspace_variables`
- `service_workspace_ownership`
- `service_artifact_sources`
- `service_vcs_repo_identifier`
- `client_admin_team_name`
- `enable_aws_preflight`

Behavior:

- bootstrap workspace name: `bootstrap-<client_id>-<env>`
- account portal workspace name: `<client_id>-<env>`
- agency-managed deployer workspace name: `<client_id>-<env>-secure-baseline`
- client-facing child deployer workspace name: `<client_id>-<env>-<project_key>`
- the account portal is a workspace factory/controller; child deployer workspaces are the actual deployers
- `service_vcs_repo_identifier` is optional in MVP; if omitted, child deployer workspaces default to this repo
- `service_artifact_sources` is reserved for deployers whose application code is built outside this repo and delivered as versioned artifacts
- `enable_aws_preflight` defaults to `false` so portal rollout can proceed before AWS OIDC trust is ready
- `services` plus `service_workspace_variables` are the initial seed only for client-facing blueprints
- `service_workspace_ownership` can override the default client-facing path for supported blueprints such as `waf` and planned `secrets`
- `secure-baseline` requires `service_workspace_variables.secure-baseline.kms_key_arn`

### `project_requests_json`

Each account portal receives a Terraform variable named `project_requests_json`.

Shape:

```json
{
  "projects": {
    "vpc": {
      "enabled": true,
      "inputs": {
        "cidr_block": "10.0.0.0/16",
        "azs": ["us-east-1a", "us-east-1b"],
        "private_subnets": ["10.0.1.0/24", "10.0.2.0/24"],
        "public_subnets": ["10.0.101.0/24", "10.0.102.0/24"]
      }
    },
    "rds": {
      "enabled": true,
      "depends_on": ["vpc"],
      "inputs": {
        "instance_class": "db.t4g.medium"
      }
    }
  }
}
```

Current client-facing blueprint catalog:

- `vpc`
- `rds`
- `dns`
- `waf`
- `lambda`
- `api`

Planned next blueprint addition:

- `secrets`

### `service_workspace_ownership`

Supported ownership overrides:

- `service_workspace_ownership.waf`
- planned `service_workspace_ownership.secrets`

Valid values:

- `client`
- `agency`

Behavior:

- `client` means WAF is provisioned as a client-facing child deployer workspace
- `agency` means WAF is provisioned as a hidden agency-managed deployer workspace
- if omitted for WAF, the default should be `client`
- only one WAF ownership mode is valid per client environment
- `client` means planned `secrets` would be provisioned as a client-facing child deployer workspace
- `agency` means planned `secrets` would be provisioned as a hidden agency-managed deployer workspace
- if omitted for planned `secrets`, the default should be `agency`
- only one `secrets` ownership mode is valid per client environment

### `service_workspace_variables.api`

The API deployer contract lives under `service_workspace_variables.api.api_config_json`.

Current sections:

- `gateway`
- `lambdas`
- `artifacts`
- `database`
- `uploads`

Current implemented API behavior:

- public regional API Gateway REST API
- Lambda authorizer plus route Lambdas
- custom domain automation
- delegated DNS integration through a sibling `dns` workspace
- uploads bucket and RDS Proxy integration

Planned WAF addition to the API contract:

- `service_workspace_variables.api.api_config_json.gateway.waf.enabled`

Planned WAF behavior in the API layer:

- API-first target integration
- reads WAF outputs from a sibling `waf` workspace
- target-owned Web ACL association by default
- planned `secret_refs` support for sibling `secrets` outputs in a later slice

### `service_workspace_variables.waf`

Planned WAF support introduces a separate deployer contract under `service_workspace_variables.waf.waf_config_json`.

WAF v1 defaults:

- separate `waf` blueprint
- `REGIONAL` only
- API-first target integration
- target-owned association by default
- optional self-attach mode with explicit `resource_arn`
- mandatory CloudWatch logging
- curated rule families only

Planned first-class rule families:

- managed rule groups
- rate rules
- IP sets plus IP allow/block rules
- geo rules
- simple header, path, and body match rules

### `service_workspace_variables.secrets`

Planned `secrets` support introduces a separate deployer contract under `service_workspace_variables.secrets.secrets_config_json`.

Planned v1 defaults:

- separate `secrets` blueprint
- AWS Secrets Manager only
- metadata-only management: Terraform creates secret containers and outputs, but not secret values
- default ownership is `agency`
- generic cross-service `secret_refs` contract
- first-class sibling consumer integration for `api` and standalone `lambda`
- first-class GitHub Actions AWS access setup in the same phase
- support both GitHub OIDC role access and static AWS key fallback, with OIDC preferred
- secure-baseline KMS key is the intended default encryption key
- RDS-generated master-user secrets remain owned by `rds`

Planned `secrets_config_json` shape:

```json
{
  "secrets": {
    "stripe_api_key": {
      "name_suffix": "stripe-api-key",
      "description": "Stripe server-side API key",
      "recovery_window_in_days": 30,
      "tags": {
        "rotation_owner": "app-team"
      }
    }
  }
}
```

Planned consumer-side `secret_refs` shape:

```json
"secret_refs": {
  "STRIPE_SECRET_ARN": "stripe_api_key"
}
```

Planned GitHub Actions setup shape:

```json
"github_actions": {
  "repositories": {
    "org/app-repo": {
      "aws_access": {
        "mode": "oidc_role"
      }
    },
    "org/legacy-repo": {
      "aws_access": {
        "mode": "static_keys",
        "access_key_id_secret_key": "github_actions_access_key_id",
        "secret_access_key_secret_key": "github_actions_secret_access_key"
      }
    }
  }
}
```

Planned behavior:

- the `secrets` workspace exposes `secret_arns` and `secret_names`
- consumer workspaces receive a sibling `secrets_workspace_name`
- `api` and `lambda` resolve `secret_refs` to secret ARNs and inject those ARNs into the declared environment-variable names
- consumer IAM should grant `secretsmanager:GetSecretValue` only for referenced secrets
- unknown secret references should fail validation before deploy
- the first `secrets` slice also standardizes GitHub Actions AWS access setup
- `github_actions.repositories[*].aws_access.mode` supports `oidc_role` and `static_keys`
- `oidc_role` is the preferred path and should provision repo-scoped AWS trust plus a role ARN output that GitHub Actions can assume
- `static_keys` is the fallback path and should model named secret containers for `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, while still keeping secret values outside Terraform state
- GitHub secret synchronization through the GitHub API or provider is not required in v1; repo-side secret population may remain a manual or later-automation step

### `service_artifact_sources`

Phase 2 introduces `service_artifact_sources` for deployers whose application code is built in a separate repository.

For `api`, the artifact source contract should provide:

- `bucket`
- `key_prefix`
- `deployment_mode`

Behavior:

- Terraform for the API stack remains in this repo
- API application code lives in a separate app repo
- the app repo publishes versioned Lambda ZIP artifacts to S3
- this repo deploys Lambda functions by artifact bucket, key, and object version

Agency-run only in MVP:

- `account-bootstrap`
- `secure-baseline`

## Architecture

### Layer 1: Agency Control Plane

The control plane lives in this repo and provisions:

- bootstrap preflight workspaces
- account portals
- agency-managed deployer workspaces
- variable-set attachment
- metadata variables
- notification wiring
- client-admin access on the visible portal surface

### Layer 2: Account Portal

Each portal is a Terraform root at [workspaces/account-portal](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/account-portal).

The portal:

- reads `project_requests_json`
- validates requested blueprints and dependency rules
- creates child deployer workspaces in the client-facing project
- attaches the right variable sets
- injects inherited metadata and OIDC env vars
- grants the configured client-admin team write access to child workspaces
- does not deploy VPC or RDS resources itself

### Layer 3: Runtime Blueprints

MVP roots:

- [workspaces/account-bootstrap](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/account-bootstrap) — hidden agency bootstrap and AWS-access preflight
- [workspaces/secure-baseline](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/secure-baseline) — hidden agency-managed baseline deployer
- [workspaces/vpc](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/vpc) — real VPC deployer
- [workspaces/rds](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/rds) — real RDS deployer
- [workspaces/dns](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/dns) — delegated public Route53 zone deployer for custom-domain environments
- [workspaces/waf](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/waf) — WAFv2 Web ACL deployer that owns the ACL, mandatory CloudWatch logging, and optional self-managed association
- [workspaces/lambda](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/lambda) — standalone Lambda deployer
- [workspaces/api](/Users/bomatra/Developement/github/cloud-infra/core-tfe-bootstrap-workspace-management/workspaces/api) — API Gateway, Lambda authorizer, Lambda handlers, uploads bucket, and RDS Proxy deployer

Planned next root:

- `workspaces/secrets` — same-account AWS Secrets Manager container workspace for sibling consumers such as `api` and standalone `lambda`

Planned API/WAF relationship:

- `api` is the first protected target that can consume WAF outputs
- the default path is target-owned association from the API workspace
- WAF can also support an advanced self-attach mode when explicitly configured with a `resource_arn`

Planned secrets relationship:

- `api` and standalone `lambda` are the first sibling consumers of `secrets`
- `secret_refs` map declared environment-variable names to logical secret keys
- the `secrets` blueprint owns secret containers, while applications fetch secret values at runtime
- the same `secrets` phase also covers GitHub Actions AWS access setup for CI/CD repositories
- OIDC role access is preferred for GitHub Actions, with static AWS key fallback only where needed
- RDS-managed master-user secrets stay in the `rds` ownership path and are not migrated into `secrets`

## Future Multi-Cloud Naming Model

Phase 1 remains AWS-first, but the naming model should evolve toward cloud-neutral client environments with provider-specific deployer identities.

Future direction:

- keep the account portal cloud-neutral: `<client_id>-<env>`
- add provider plus target identity to bootstrap and deployer workspace names
- prefer cloud-neutral blueprint names in the control plane
- map those blueprints to provider-specific implementations underneath

Target patterns:

- account portal: `<client_id>-<env>`
- bootstrap/preflight: `bootstrap-<client_id>-<env>-<provider>-<target_key>`
- foundation deployer: `<client_id>-<env>-<provider>-foundation`
- child deployer: `<client_id>-<env>-<provider>-<blueprint>`
- regional child deployer when needed: `<client_id>-<env>-<provider>-<region_or_location>-<blueprint>`

Example cloud-neutral blueprint aliases:

- `foundation`
- `network`
- `postgres`
- `kubernetes`
- `object-storage`
- `dns`
- `observability`

Example provider mappings:

- `network` → AWS `vpc`, Azure `vnet`, GCP `vpc`
- `postgres` → AWS `rds`, Azure `postgres-flex`, GCP `cloudsql`
- `kubernetes` → AWS `eks`, Azure `aks`, GCP `gke`

## Phase Plan

### Phase 0 — Spec Consolidation

- [x] create this canonical spec
- [x] keep the older framework spec and TODO doc as historical references
- [x] mark the YAML/catalog pipeline as historical rather than active target
- [x] carry forward completed control-plane work instead of reopening it

### Phase 1 — Fast MVP

- [x] keep `accounts.tf.json` as the onboarding contract
- [x] extend account metadata with `client_admin_team_name`
- [x] make `service_vcs_repo_identifier` optional by defaulting child deployer workspaces to the control-plane repo
- [x] add `project_requests_json` as the account-portal contract
- [x] create `workspaces/account-portal`
- [x] add opt-in bootstrap AWS preflight so portal rollout is not blocked on target-account trust setup
- [x] convert the client-facing placeholder workspace into a real account portal keyed by environment context
- [x] fix visible naming and derived dependency workspace names to use the environment-based workspace prefix
- [x] support account portal creation plus `vpc` and `rds` child-project creation
- [x] keep `secure-baseline` agency-managed in the hidden project path
- [x] add basic client-admin access and approval-gated client-facing workspaces (`auto_apply = false`)
- [ ] prove the full end-to-end HCP Terraform flow against a real account
- [ ] document the client-admin handoff runbook in operational detail

### Phase 2 — Governance And Safety

- [ ] tighten RBAC beyond basic `write` access
- [ ] add explicit boundaries between agency-set and client-set variables
- [ ] add policy hooks and approval policy integration points
- [ ] add drift detection for client-facing child deployer workspaces
- [ ] add stronger schema validation for `project_requests_json`
- [x] add `api`, `lambda`, and `dns` to the portal blueprint catalog
- [x] add `api` dependency rules on `secure-baseline`, `vpc`, and `rds`
- [x] infer `api` dependency on `dns` when custom domains omit `hosted_zone_id`
- [x] create `workspaces/api` in this repo
- [x] create `workspaces/lambda` in this repo
- [x] create `workspaces/dns` in this repo
- [x] provision a public regional API Gateway REST API
- [x] provision one Lambda authorizer with pluggable external OIDC provider config
- [x] provision one main CRUD Lambda
- [x] provision one presign Lambda for upload and download URL issuance
- [x] provision one private uploads bucket with KMS encryption
- [x] provision RDS Proxy and target group for Lambda-to-Postgres connectivity
- [x] provision Lambda IAM roles, VPC networking, and security groups
- [x] provision CloudWatch log groups, API access logs, and basic alarms for 5XX and Lambda errors
- [x] keep API Terraform in this repo while the application code can be delivered separately as versioned artifacts
- [x] validate API artifact and auth inputs at the control-plane and portal layers so bad config fails before deploy
- [x] add a `dns` blueprint for delegated public Route53 zones used by API custom domains
- [x] allow `api` custom domains to inherit hosted zone IDs from a sibling `dns` workspace when `hosted_zone_id` is omitted
- [x] document the manual parent-zone NS delegation and cutover workflow for delegated API environments

#### Phase 2A — WAF Blueprint

- [ ] add `service_workspace_ownership.waf` to the onboarding contract with valid values `client` and `agency`
- [ ] add `service_workspace_variables.waf.waf_config_json`
- [ ] add `service_workspace_variables.api.api_config_json.gateway.waf.enabled`
- [ ] add `waf` as a supported blueprint in the control plane
- [ ] create `modules/aws/waf-web-acl`
- [ ] create `workspaces/waf`
- [ ] provision a regional WAFv2 Web ACL with `REGIONAL` scope only in v1
- [ ] support curated rule families: managed rule groups, rate rules, IP sets plus IP allow/block rules, geo rules, and simple header/path/body match rules
- [ ] validate unique priorities across all WAF rule families
- [ ] create mandatory CloudWatch logging for WAF with the AWS-required log-group naming convention
- [ ] redact sensitive headers by default in WAF logs
- [ ] create target-owned Web ACL association from the API workspace using sibling WAF outputs
- [ ] support optional self-attach mode only when explicitly configured with a `resource_arn`
- [ ] extend bootstrap IAM for `wafv2:*`
- [ ] document WAF ownership modes, logging behavior, and v1 scope limits
- [ ] defer CloudFront/global protection, ALB support, raw statement escape hatches, and alternate log sinks like Firehose or S3 to a later slice

- [ ] add API keys, usage plans, and quotas as the next API Gateway capability slice after WAF

#### Phase 2B — Secrets Blueprint

- [ ] add `service_workspace_ownership.secrets` to the onboarding contract with valid values `client` and `agency`
- [ ] default omitted `service_workspace_ownership.secrets` to `agency`
- [ ] add `service_workspace_variables.secrets.secrets_config_json`
- [ ] add `secret_refs` and `secrets_workspace_name` as the generic sibling-consumer contract
- [ ] add a `github_actions` section under `secrets_config_json` for repository-specific AWS access setup
- [ ] add `secrets` as a supported blueprint in the control plane
- [ ] create `modules/aws/secrets-manager`
- [ ] create `workspaces/secrets`
- [ ] provision same-account AWS Secrets Manager secret containers without creating secret values in Terraform
- [ ] expose `secret_arns` and `secret_names`
- [ ] add sibling consumer integration for `api` and standalone `lambda`
- [ ] inject resolved secret ARNs into declared environment-variable names
- [ ] grant `secretsmanager:GetSecretValue` only for referenced secrets
- [ ] validate bad secret references and missing sibling outputs clearly
- [ ] document metadata-only v1 behavior so secret values are managed outside Terraform state
- [ ] keep RDS-generated master-user secrets owned by `rds`
- [ ] support GitHub Actions AWS access in the same phase
- [ ] support `oidc_role` and `static_keys` modes for GitHub Actions repositories, with OIDC preferred
- [ ] provision repo-scoped OIDC trust and assumable role outputs for the preferred GitHub Actions path
- [ ] model named secret containers for static AWS key fallback without storing secret values in Terraform state
- [ ] defer SSM Parameter Store, rotation Lambda automation, cross-account sharing, Terraform-managed secret values, and GitHub secret-sync automation to later slices

### Phase 3 — Orchestration

- [ ] add dependency-aware ordering beyond validation
- [ ] add reusable context/default inheritance across blueprints
- [ ] add richer orchestration comparable to Spacelift stack dependencies plus Atmos composition
- [ ] reassess whether runtime orchestration should move into a companion repo only after the portal contract is proven

### Phase 4 — Expansion

- [ ] add `s3-secure`
- [ ] add `eks`
- [ ] add observability and backup baselines
- [ ] add cost controls, release/versioning flow, and operator runbooks

### Phase 5 — Multi-Cloud Naming And Target Abstraction

- [ ] keep the visible account portal name cloud-neutral as `<client_id>-<env>`
- [ ] extend the onboarding contract from AWS-account-centric metadata to provider-neutral target metadata
- [ ] add `provider` and `target_key` as first-class identity fields for deployer naming
- [ ] support target-specific identifiers such as AWS `account_id`, Azure `subscription_id`, and GCP `project_id`
- [ ] introduce cloud-neutral blueprint aliases in the control plane such as `foundation`, `network`, and `postgres`
- [ ] map cloud-neutral blueprints to provider-specific implementations without changing the client-facing request model
- [ ] move bootstrap/preflight naming to `bootstrap-<client_id>-<env>-<provider>-<target_key>`
- [ ] move child deployer naming to `<client_id>-<env>-<provider>-<blueprint>` with optional regional suffixes where required
- [ ] support multiple targets per client environment, for example `aws-primary`, `azure-primary`, and `gcp-analytics`
- [ ] add a compatibility and migration plan for existing AWS workspace names and state addresses
- [ ] document naming rules that forbid cloud-specific business names from becoming the primary control-plane identity

## MVP Acceptance Tests

- [ ] one edit to `accounts.tf.json` creates a bootstrap workspace and account portal for a new client environment
- [ ] a shared AWS account can appear in both `dev` and `workbench` without workspace-name collisions
- [ ] a client admin updates `project_requests_json` to request `vpc`, and the portal creates the child deployer `<client_id>-<env>-vpc` with inherited region, tier, IAM role, and metadata
- [ ] an `rds` request fails with a clear validation error unless `vpc` and required inputs already exist
- [ ] bootstrap workspaces stay hidden from the client team while client-facing applies remain approval-gated
- [ ] onboarding succeeds through `account-bootstrap`, `secure-baseline`, `vpc`, and `rds`
- [ ] a `waf` workspace can create a regional Web ACL with mandatory CloudWatch logging
- [ ] an API workspace with `gateway.waf.enabled = true` can attach a sibling WAF Web ACL successfully
- [ ] WAF ownership mode can be agency-managed or client-facing without changing the WAF contract
- [ ] a `secrets` workspace can create secret containers without creating secret values
- [ ] omitted `service_workspace_ownership.secrets` defaults to agency-managed `secrets`
- [ ] explicit `client` ownership can create visible `<client_id>-<env>-secrets`
- [ ] `api` and standalone `lambda` can consume sibling secret outputs through `secret_refs`
- [ ] invalid `secret_refs` fail with a clear validation error
- [ ] GitHub Actions repositories can be configured for OIDC role access through the `secrets` phase
- [ ] GitHub Actions static AWS key fallback can be modeled without putting secret values into Terraform state
- [ ] RDS-managed database secrets remain unchanged

Explicitly not release blockers for MVP:

- drift detection
- policy packs
- `s3-secure`
- `eks`
- multi-cloud naming and target abstraction
- CloudFront/global WAF protection
- ALB WAF protection
- raw AWS WAF statement escape hatch
- alternate WAF log sinks such as Firehose or S3
- async jobs and background workers for the `api` blueprint

## Assumptions

- Phase 1 stays Terraform/OpenTofu only
- HCP Terraform remains the primary execution engine and state backend
- day-1 users are agency operators plus one client-admin team per account
- phase 1 self-service is HCP workspace-variable/API driven, not a Git-backed client repo flow
- visible workspace names are environment-scoped, so the same AWS account can be reused across multiple environments when needed
- no repo split is required before MVP acceptance

## Historical References

- [Agency-AWS-Terraform-Framework-Spec.md](./Agency-AWS-Terraform-Framework-Spec.md)
- [Agency-AWS-Terraform-Implementation-TODO.md](./Agency-AWS-Terraform-Implementation-TODO.md)
- [Open-Source-Framework-Research.md](./Open-Source-Framework-Research.md)
