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

MVP blueprint catalog:

- `vpc`
- `rds`

Phase 2 blueprint additions:

- `api`

### `service_workspace_variables.api`

Phase 2 introduces an `api` deployer contract under `service_workspace_variables.api`.

Expected fields:

- `artifact_version`
- `cors_allowed_origins`
- `auth_providers`
- `default_auth_provider`
- `lambda_memory_mb`
- `lambda_timeout_seconds`
- `uploads_bucket_enabled`

`auth_providers` is a map keyed by provider name. Each value contains:

- `issuer_url`
- `audiences`

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

Planned Phase 2 root:

- `workspaces/api` — API Gateway, Lambda authorizer, Lambda handlers, S3 uploads, and RDS Proxy deployer

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
- [ ] add `api` to the portal blueprint catalog
- [ ] add `api` dependency rules on `secure-baseline`, `vpc`, and `rds`
- [ ] create `workspaces/api` in this repo
- [ ] provision a public regional API Gateway REST API
- [ ] provision one Lambda authorizer with pluggable external OIDC provider config
- [ ] provision one main CRUD Lambda
- [ ] provision one presign Lambda for upload and download URL issuance
- [ ] provision one private uploads bucket with KMS encryption
- [ ] provision RDS Proxy and target group for Lambda-to-Postgres connectivity
- [ ] provision Lambda IAM roles, VPC networking, and security groups
- [ ] provision CloudWatch log groups, API access logs, and basic alarms for 5XX and Lambda errors
- [ ] extend `service_workspace_variables.api` with `artifact_version`, `cors_allowed_origins`, `auth_providers`, `default_auth_provider`, `lambda_memory_mb`, `lambda_timeout_seconds`, and `uploads_bucket_enabled`
- [ ] define `auth_providers` as a map keyed by provider name with `issuer_url` and `audiences`
- [ ] add `service_artifact_sources.api` for S3 artifact delivery from the separate app repo
- [ ] keep API Terraform in this repo while the Node/TypeScript application code lives in a separate repo
- [ ] document the app-repo release flow: build Lambda ZIPs, upload to a versioned S3 artifact bucket, deploy from bucket/key/object-version
- [ ] validate API artifact and auth inputs at the control-plane and portal layers so bad config fails before deploy
- [ ] document client-admin and operator workflow for bumping `artifact_version` and promoting API releases safely

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

Explicitly not release blockers for MVP:

- drift detection
- policy packs
- `s3-secure`
- `eks`
- multi-cloud naming and target abstraction
- custom domain, WAF, async jobs, and background workers for the `api` blueprint

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
