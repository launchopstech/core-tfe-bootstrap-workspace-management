# core-tfe-bootstrap-workspace-management

Terraform control plane for managing HCP Terraform workspaces, projects, and variable sets across multiple clients and AWS accounts.

Canonical architecture and roadmap: [Agency-Orchestration-Platform-Spec.md](./Agency-Orchestration-Platform-Spec.md)

---

## Purpose

This repository is the **agency control plane**. It does not deploy AWS infrastructure directly — instead it provisions and configures the HCP Terraform workspaces that will deploy AWS infrastructure for each client.

When you add a client account to this repo and apply, HCP Terraform automatically gets:

- a bootstrap workspace named `bootstrap-<client>-<env>` inside the agency project
- an account portal workspace named `<client>-<env>` inside the client-facing project
- the right variable sets attached (global defaults + environment-specific + security-tier-specific)
- workspace metadata variables pre-populated (account ID, region, client ID, environment, security tier, selected services)
- account-portal contract variables pre-populated (`project_requests_json`, project repo settings, variable-set IDs, run-role ARN)
- failure notifications wired up
- an agency-managed `secure-baseline` deployer workspace named `<client>-<env>-secure-baseline` when the account opts into it
- client-facing `vpc` and `rds` deployer workspaces created by the account portal from `project_requests_json`

Every new account follows the same pattern with zero manual clicking in the HCP Terraform UI.

In practice, the visible model is:

- `bootstrap-<client>-<env>` = hidden agency bootstrap and AWS-access preflight
- `<client>-<env>` = client-facing portal and workspace factory
- `<client>-<env>-vpc` = real VPC deployer
- `<client>-<env>-rds` = real RDS deployer (single instance or Aurora cluster via `enable_cluster`)
- `<client>-<env>-secure-baseline` = hidden agency-managed baseline deployer

---

## Repository Structure

```
hcp-bootstrap/                        # Step 1 — run locally once
bootstrap-accounts-varset/            # Step 2 — runs in HCP Terraform
bootstrap-accounts-dev/               # Step 3a — runs in HCP Terraform (dev accounts)
  accounts.tf.json                    # ← only metadata file needed to onboard a client
bootstrap-accounts-workbench/         # Step 3b — runs in HCP Terraform (workbench accounts)
  accounts.tf.json                    # ← same for workbench accounts
bootstrap-accounts/                   # Shared module — called by dev and workbench roots
modules/                              # Reusable AWS service modules
  aws/
    account-bootstrap/
    secure-baseline/
    vpc/
    rds-secure/                       # Single RDS instance (PostgreSQL)
    rds-aurora/                       # Aurora PostgreSQL cluster
    eks/
    s3-secure/
    iam-access/
workspaces/                           # Per-service workspace roots (run in HCP Terraform)
  account-portal/                     # portal/factory that creates child deployers
  account-bootstrap/                  # agency bootstrap and OIDC preflight
  vpc/                                # real VPC deployer
  rds/                                # real RDS deployer (single instance or Aurora cluster)
  secure-baseline/                    # hidden agency baseline deployer
scripts/
  local-backend-setup.sh              # Generate override files for local CLI plan/apply
docs/
  token-strategy.md                   # HCP Terraform token types and placement
```

**`accounts.tf.json` is the only file you edit to onboard a client.** No Python scripts, no YAML pipeline, no generated files.

---

## How It Works — The Four Layers

```
┌────────────────────────────────────────────────────────────┐
│  hcp-bootstrap/  (run locally, once per repo setup)        │
│  Creates 3 control-plane workspaces in HCP Terraform       │
└────────────────────┬───────────────────────────────────────┘
                     │ creates
                     ▼
┌────────────────────────────────────────────────────────────┐
│  Workspace: 00-bootstrap-account-workspace-management      │
│  Root: bootstrap-accounts-varset/                          │
│  Creates: 5 HCP projects, variable sets, publishes IDs     │
└─────────┬──────────────────────────────────────────────────┘
          │ tfe_outputs (project IDs + variable set IDs)
          ├──────────────────────────┐
          ▼                          ▼
┌──────────────────────┐  ┌───────────────────────────────┐
│ Workspace:           │  │ Workspace:                     │
│ bootstrap-account-   │  │ bootstrap-account-             │
│ workspace-mgmt-dev   │  │ workspace-mgmt-workbench       │
│ Root: bootstrap-     │  │ Root: bootstrap-               │
│ accounts-dev/        │  │ accounts-workbench/            │
└──────────┬───────────┘  └──────────────┬─────────────────┘
           │ calls module                │ calls module
           └──────────────┬─────────────┘
                          ▼
           ┌──────────────────────────────┐
           │  bootstrap-accounts/         │
           │  Shared module               │
           │  For each account entry:       │
           │  - bootstrap preflight         │
           │  - account portal / factory    │
           │  - agency-managed deployers    │
           │  - variable sets + metadata    │
           │  - notifications + portal vars │
           └──────────────────────────────┘
```

---

## Workspace Roles

| Workspace | Role |
|---|---|
| `bootstrap-<client>-<env>` | Hidden agency bootstrap and AWS-access preflight. Verifies HCP Terraform OIDC is targeting the expected AWS account before downstream deployers run. |
| `<client>-<env>` | Client-facing account portal and workspace factory. Reads `project_requests_json`, validates requests, and creates child deployer workspaces. |
| `<client>-<env>-secure-baseline` | Hidden agency-managed baseline deployer. |
| `<client>-<env>-vpc` | Real VPC deployer workspace. |
| `<client>-<env>-rds` | Real RDS deployer workspace. Deploys single PostgreSQL instance by default; set `enable_cluster = true` for Aurora PostgreSQL. |

---

## Cross-Workspace Data Flow

Deployer workspaces need outputs from upstream workspaces (e.g., RDS needs the KMS key from secure-baseline and subnet IDs from VPC). Data flows in two ways:

**Variable injection (cross-project values):** Values known at bootstrap time (e.g., `kms_key_arn` from the CFN stack) are placed in `accounts.tf.json` under `service_workspace_variables`. The control plane seeds them into `project_requests_json`, the portal injects them as workspace variables on child deployers. No cross-workspace state access needed.

**`tfe_outputs` (same-project runtime values):** Values only known after a workspace applies (e.g., `vpc_id`, `database_subnet_group_name`) are read at runtime via `data.tfe_outputs`. This requires the source workspace to have `global_remote_state = true`, which is set automatically when other services in the account depend on it.

```
accounts.tf.json
  kms_key_arn ──────→ project_requests_json ──→ portal injects on RDS workspace
                                                  └─ var.kms_key_arn (direct)

secure-baseline (global_remote_state = true)
  logs_bucket_arn ──→ VPC reads via tfe_outputs at runtime

VPC (global_remote_state = true)
  vpc_id ───────────→ RDS reads via tfe_outputs at runtime
  database_subnet_group_name
  private_subnet_cidrs
```

Dependency workspace names (e.g., `vpc_workspace_name`, `secure_baseline_workspace_name`) are auto-injected by the portal based on the dependency graph in `project_catalog`.

---

## Terraform Roots

### `hcp-bootstrap/`

**Run this locally, once, when setting up the repo for the first time.**

Creates the three control-plane workspaces in HCP Terraform. These workspaces are what runs the remaining steps — they point back at this repo via VCS integration.

**What it creates:**

| Workspace Name | Working Directory | Purpose |
|---|---|---|
| `00-bootstrap-account-workspace-management` | `bootstrap-accounts-varset/` | Manages projects and variable sets |
| `bootstrap-account-workspace-management-dev` | `bootstrap-accounts-dev/` | Manages dev bootstrap workspaces |
| `bootstrap-account-workspace-management-workbench` | `bootstrap-accounts-workbench/` | Manages workbench bootstrap workspaces |

**How to run:**

```bash
terraform login   # authenticate to app.terraform.io
export TF_CLOUD_ORGANIZATION=core-aws   # or your non-default HCP Terraform org
cd hcp-bootstrap
terraform init
terraform plan
terraform apply
```

**Inputs (variables):** `organization`, `vcs_repo_identifier`, `vcs_branch`, `vcs_oauth_token_id`, `terraform_version`

---

### `bootstrap-accounts-varset/`

**Runs inside HCP Terraform** — workspace `00-bootstrap-account-workspace-management`.

Creates the shared HCP Terraform projects and variable sets that all bootstrap workspaces share. Must run before `bootstrap-accounts-dev` or `bootstrap-accounts-workbench`.

**What it creates:**

**Projects** (one per environment):

| Project | Environment |
|---|---|
| `bootstrap-sbx` | sandbox |
| `bootstrap-dev` | development |
| `bootstrap-qa` | QA / staging |
| `bootstrap-prod` | production |
| `bootstrap-workbench` | workbench / spike |

**Variable sets** (attached to workspaces by the shared module):

| Variable Set | Scope | Variables injected |
|---|---|---|
| `bootstrap-accounts-global` | all workspaces | none by default — reserved for future shared defaults |
| `bootstrap-accounts-<env>` | per environment (sbx/dev/qa/prod/workbench) | `environment` |
| `bootstrap-accounts-<tier>` | per security tier (standard/high) | `security_tier` |
| `bootstrap-accounts-control-plane-secrets` | optional — all workspaces | sensitive values (if provided) |

**Outputs** (consumed by `bootstrap-accounts-dev` and `bootstrap-accounts-workbench` via `tfe_outputs`):

- `bootstrap_global_variable_set_id`
- `environment_variable_set_ids` — map of env → variable set ID
- `security_tier_variable_set_ids` — map of tier → variable set ID
- `control_plane_secrets_variable_set_id`
- `project_ids` — map of all 5 project IDs
- `bootstrap_dev_project_id`, `bootstrap_workbench_project_id`

**How to apply:** push to `main` or trigger a run in HCP Terraform on `00-bootstrap-account-workspace-management`.

---

### `bootstrap-accounts-dev/`

**Runs inside HCP Terraform** — workspace `bootstrap-account-workspace-management-dev`.

Manages bootstrap workspaces for all **dev** AWS accounts. Reads account entries from `accounts.tf.json` and calls the shared `bootstrap-accounts` module, passing the `bootstrap-dev` project ID from `bootstrap-accounts-varset` outputs.

#### One account or many

The map key in `accounts.tf.json` is just a stable unique entry key. The actual AWS account ID lives in the `account_id` field. This means:

**One AWS account per environment (recommended for production clients):**
```
bootstrap-accounts-dev/accounts.tf.json       → "333333333333" (dedicated dev account)
bootstrap-accounts-workbench/accounts.tf.json → "222222222222" (dedicated workbench account)
```
Each environment is fully isolated — separate billing, separate IAM, separate blast radius.

Visible workspaces are environment-scoped, so the same AWS account can appear in both `dev` and `workbench` when needed.

**How to add a dev account:**

Edit `bootstrap-accounts-dev/accounts.tf.json`:

```json
{
  "locals": {
    "accounts": {
      "123456789012": {
        "account_id": "123456789012",
        "client_id": "acme",
        "account_name": "acme.dev",
        "env": "dev",
        "region": "us-east-1",
        "enable_aws_preflight": false,
        "security_tier": "standard",
        "services": ["account-bootstrap", "secure-baseline", "vpc", "rds"],
        "service_family": "platform",
        "vcs_repo_identifier": "your-org/your-repo",
        "client_admin_team_name": "acme-platform-admins"
      }
    }
  }
}
```

Commit and push to `main`. The HCP Terraform workspace picks up the change and creates the workspace automatically.

If you want the account portal pre-seeded with `vpc` or `rds` requests, add the required `service_workspace_variables` for those services. `service_vcs_repo_identifier` is optional in MVP; if omitted, child deployer workspaces default back to this repo’s `workspaces/<blueprint>/` roots.

**`accounts.tf.json` schema:**

The key for each entry is any stable unique identifier for that account entry. The 12-digit AWS account ID is supplied in the `account_id` field and validated by the bootstrap module at plan time.

| Field | Required | Allowed values / default | Description |
|---|---|---|---|
| `account_id` | yes | 12-digit AWS account ID | AWS account targeted by the bootstrap and service workspaces |
| `client_id` | yes* | any lowercase string | Unique client identifier — used in workspace name and tags. Use `product_name` as fallback if not set. |
| `product_name` | yes* | any lowercase string | Fallback for `client_id`. One of the two must be set. |
| `account_name` | no | default: account ID | Human-readable label for this account (e.g. `acme.dev`) |
| `env` | yes | `dev`, `qa`, `prod`, `workbench`, `sbx` | Environment label — controls which variable set is attached and which HCP Terraform project the workspace lands in |
| `region` | no | any AWS region, default: `us-east-1` | AWS region for this account |
| `enable_aws_preflight` | no | default: `false` | When `true`, the hidden bootstrap workspace verifies HCP Terraform OIDC can assume `TerraformDeployRole` in the target AWS account. Leave `false` until AWS trust is ready. |
| `security_tier` | yes | `standard`, `high` | Controls which security-tier variable set is attached |
| `services` | no | default: `[]` | Desired services for this account. Used to seed agency-managed workspaces (`secure-baseline`) and initial account-portal `project_requests_json` entries for client-facing blueprints such as `vpc`, `rds`, `dns`, `lambda`, and `api` |
| `service_family` | no | any string, default: `platform` | Logical service grouping — used as a workspace tag |
| `client_admin_team_name` | no | HCP Terraform team name | If set, the named team gets write access to the account portal and any client-facing child deployer workspaces it creates |
| `vcs_repo_identifier` | yes | `org/repo` format | GitHub repo the workspace VCS integration points at |
| `service_vcs_repo_identifier` | no | `org/repo` format | Optional override repo for child deployer workspaces. If omitted, the portal uses the same repo as `vcs_repo_identifier` |
| `service_workspace_variables` | no | map keyed by service name | Terraform variables used to seed agency-managed workspaces and the initial portal request document, for example `kms_key_arn` for `secure-baseline`, network CIDRs for `vpc`, delegated-zone config for `dns`, Lambda packaging/runtime config for `lambda`, and API contract/config for `api` |
| `working_directory` | no | default: `workspaces/account-bootstrap` | Working directory inside the VCS repo for the bootstrap workspace |
| `workspace_tags` | no | list of strings, default: `[]` | Additional HCP Terraform tags to apply to the workspace |

**Validation rules (enforced by Terraform `precondition` at plan time):**
- `account_id` must be a 12-digit AWS account ID
- `env` must be one of: `dev`, `qa`, `prod`, `workbench`, `sbx`
- `security_tier` must be one of: `standard`, `high`
- `client_id` or `product_name` must be non-empty
- `vcs_repo_identifier` must be set to a real repo — cannot be the default placeholder
- `service_vcs_repo_identifier` is optional; the portal defaults to `vcs_repo_identifier` when it is omitted
- `enable_aws_preflight = true` requires the target AWS account to already trust HCP Terraform OIDC for `arn:aws:iam::<account_id>:role/TerraformDeployRole`
- `secure-baseline` requires `service_workspace_variables["secure-baseline"].kms_key_arn`
- `vpc` requires `service_workspace_variables["vpc"].cidr_block`, `azs`, `private_subnets`, and `public_subnets`
- `rds` requires both `secure-baseline` and `vpc` in `services`
- `rds` requires `service_workspace_variables["rds"].kms_key_arn` (the platform KMS key ARN from the CFN bootstrap)
- if `rds` is enabled, `service_workspace_variables["vpc"].database_subnets` is also required so the VPC workspace can create a DB subnet group
- `dns` requires `service_workspace_variables["dns"].dns_config_json.zone_name`
- if `api` includes any Lambda with `needs_db = true`, `service_workspace_variables["api"].api_config_json` must include `database.iam_username` for an existing DB role that can use IAM auth through RDS Proxy
- `service_workspace_variables["lambda"].lambda_config_json` and `service_workspace_variables["api"].api_config_json` should be nested JSON objects in `accounts.tf.json`, not quoted JSON strings
- `service_workspace_variables["api"].api_config_json.gateway.custom_domains` is optional and supports same-account Route53 automation for API Gateway custom domains; each entry requires `domain_name` and either `hosted_zone_id` or a sibling `dns` workspace that provides the delegated hosted zone output

**Delegated DNS + API custom domain example (`service_workspace_variables` excerpts):**

```json
{
  "dns": {
    "dns_config_json": {
      "zone_name": "dev.example.com"
    }
  },
  "api": {
    "api_config_json": {
      "gateway": {
        "enabled": true,
        "stage": { "name": "v1" },
        "custom_domains": {
          "primary": {
            "domain_name": "api.dev.example.com",
            "base_path": ""
          }
        }
      }
    }
  }
}
```

Recommended rollout for delegated DNS:
- add `dns` to `services` and apply the control plane so `<client>-<env>-dns` is created
- apply `<client>-<env>-dns` first and copy the `name_servers` output
- manually add NS delegation for the delegated zone in the parent DNS zone
- wait for delegation to propagate
- apply `<client>-<env>-api` so ACM validation and the API Gateway custom domain can complete inside that delegated zone

See [DNS and API Custom Domains](docs/runbooks/dns-api-custom-domains.md) for
the detailed Route53 + GoDaddy runbook, including the difference between
delegating a subdomain and moving an entire registered domain to Route53.

Parent-zone delegation note:
- if the parent zone is hosted in GoDaddy DNS, add an `NS` record for the delegated label there
- example for `api.dev.mindrithm.app`: create the delegated Route53 zone `dev.mindrithm.app`, then add an `NS` record for host `dev` in the parent `mindrithm.app` zone that points to the 4 Route53 `name_servers`
- if GoDaddy is only the registrar and the parent zone uses different authoritative nameservers, make the NS change in the actual DNS host for the parent zone instead of in GoDaddy
- do not change the registrar nameservers for the whole domain just to delegate a subdomain
- do not create manual `A`, `CNAME`, or ACM validation records for `api.dev.mindrithm.app` in the parent zone; once `dev.mindrithm.app` is delegated, Terraform manages those records inside Route53

Manual `hosted_zone_id` still works when you already have a same-account Route53 public hosted zone and do not want to create a sibling `dns` workspace.

---

### `bootstrap-accounts-workbench/`

**Runs inside HCP Terraform** — workspace `bootstrap-account-workspace-management-workbench`.

Identical to `bootstrap-accounts-dev/` but targets the `bootstrap-workbench` project. Used for spike, prototyping, and client workbench accounts that are not tied to the dev lifecycle.

**How to add a workbench account:**

Edit `bootstrap-accounts-workbench/accounts.tf.json` using the same format as the dev accounts example, with `"env": "workbench"`.

You can reuse the same AWS account ID here as in `bootstrap-accounts-dev/accounts.tf.json`. The visible workspace names are environment-based, so `dev` and `workbench` do not collide.

---

### `bootstrap-accounts/` (shared module)

Not a root — called by `bootstrap-accounts-dev` and `bootstrap-accounts-workbench`. Do not apply directly.

**For each account entry it creates:**

1. **`tfe_workspace`** — bootstrap workspace named `bootstrap-<client_id>-<env>`
   - acts as the hidden agency bootstrap and AWS-access preflight workspace
   - AWS preflight is controlled by `enable_aws_preflight` and defaults to off
   - tagged with `bootstrap`, `workspace-class-bootstrap-account`, `client-<id>`, `env-<env>`, `tier-<tier>`, `family-<family>`
   - linked to VCS repo, points to the account's working directory
   - `auto_apply = true`, `execution_mode = remote`

2. **`tfe_workspace`** — account portal workspace named `<client_id>-<env>`
   - acts as the client-facing portal and workspace factory
   - tagged with `workspace-class-account-portal`, `account-<account_id>`, `client-<id>`, `env-<env>`, `tier-<tier>`
   - linked to `workspaces/account-portal`
   - pre-seeded with `project_requests_json` and child-workspace settings
   - `auto_apply = false`, `execution_mode = remote`

3. **`tfe_workspace_variable_set`** — attaches shared variable sets to bootstrap, account-portal, and agency-managed deployer workspaces:
   - global (all workspaces)
   - environment-specific (matches `env` field)
   - security-tier-specific (matches `security_tier` field)
   - secrets (if configured)

4. **`tfe_variable`** — writes metadata directly into workspaces as Terraform variables:
   - `client_id`, `aws_account_id`, `aws_account_name`, `environment`, `aws_region`, `security_tier`, `service_family`, `selected_services`

5. **Optional agency-managed `tfe_workspace` deployer workspaces** — currently `secure-baseline`
   - named `<client_id>-<env>-secure-baseline`
   - run in the agency project, not the client-facing project
   - default to this repo unless `service_vcs_repo_identifier` overrides the project repo

6. **`tfe_notification_configuration`** — sends email on `run:errored` if notifications are enabled

7. **`tfe_team_access`** — grants the optional `client_admin_team_name` write access to the account portal and client-facing child workspaces

**Outputs:**

```hcl
bootstrap_account_workspaces = {
  "<account_entry_key>" = {
    id                = "ws-xxxx"
    name              = "bootstrap-acme-dev"
    working_directory = "workspaces/account-bootstrap"
    tag_names         = [...]
    project_id        = "prj-xxxx"
    metadata          = { client_id, aws_account_id, environment, ... }
  }
}
```

---

## Execution Order

These steps must be applied in order. Each step depends on outputs from the previous step.

```
Step 1 — run locally
──────────────────────────────────────────────
cd hcp-bootstrap
terraform login
terraform init && terraform plan && terraform apply

Step 2 — trigger in HCP Terraform UI or via push to main
──────────────────────────────────────────────
Workspace: 00-bootstrap-account-workspace-management
Root:      bootstrap-accounts-varset/

Step 3 — trigger in HCP Terraform UI or via push to main
──────────────────────────────────────────────
Workspace: bootstrap-account-workspace-management-dev
Root:      bootstrap-accounts-dev/

Workspace: bootstrap-account-workspace-management-workbench
Root:      bootstrap-accounts-workbench/
```

Steps 2 and 3 are also triggered automatically by any push to `main` via VCS integration.

---

## Adding a New Client Account — Quick Reference

1. Decide the environment: dev → edit `bootstrap-accounts-dev/accounts.tf.json`, workbench → edit `bootstrap-accounts-workbench/accounts.tf.json`
2. Add the account entry using a stable unique key and set the real AWS `account_id` inside the object
3. Set `client_id`, `env`, `region`, `security_tier`, `services`, `vcs_repo_identifier`
4. If you want the account portal pre-seeded with client-facing `vpc` and `rds` requests, provide `service_workspace_variables` for those blueprints
5. Optionally set `service_vcs_repo_identifier` if child deployer workspaces should point to a different repo than the control-plane repo
6. Commit and push to `main`
7. HCP Terraform runs automatically and the workspace appears in the correct project

For local CLI runs against a non-default org, export `TF_CLOUD_ORGANIZATION=<your-org>` before running Terraform in `bootstrap-accounts-varset/`, `bootstrap-accounts-dev/`, or `bootstrap-accounts-workbench/`.

---

## Workspace Naming Convention

| Class | Pattern | Visible to client | Example |
|---|---|:---:|---|
| Control plane — varset | `00-bootstrap-account-workspace-management` | No | — |
| Control plane — env manager | `bootstrap-account-workspace-management-<env>` | No | `bootstrap-account-workspace-management-dev` |
| Bootstrap account | `bootstrap-<client_id>-<env>` | No | `bootstrap-acme-dev` |
| Account portal | `<client_id>-<env>` | Yes | `acme-dev` |
| Agency project | `<client_id>-<env>-secure-baseline` | No | `acme-dev-secure-baseline` |
| Project (client self-service) | `<client_id>-<env>-<blueprint>` | Yes | `acme-dev-vpc` |

The bootstrap layer is agency-internal. Clients log into HCP Terraform and see their environment workspace. That portal is a workspace factory: it reads `project_requests_json`, creates child deployers like `acme-dev-vpc`, `acme-dev-dns`, and `acme-dev-api`, and injects the inherited metadata those deployers need to run.

---

## Variable Set Hierarchy

Each bootstrap workspace gets variable sets attached in this order of specificity:

```
bootstrap-accounts-global          (applies to all workspaces)
    └── bootstrap-accounts-<env>   (applies to workspaces in that environment)
    └── bootstrap-accounts-<tier>  (applies to workspaces at that security tier)
    └── bootstrap-accounts-control-plane-secrets  (optional, sensitive values)
```

More specific sets override less specific ones where keys collide.

---

## Prerequisites

- Terraform >= 1.0
- HCP Terraform account at `app.terraform.io` with organization `core-aws`
- VCS OAuth token configured in HCP Terraform (GitHub integration)
- `terraform login` completed locally for `hcp-bootstrap/` step

---

## Local CLI Plan & Apply

You can run `terraform plan` and `terraform apply` from your local machine against any HCP Terraform workspace. Runs execute **remotely** in HCP Terraform (OIDC credentials, variable sets, and all workspace config apply as normal) — your terminal streams the output.

### One-time setup

```bash
# 1. Authenticate to HCP Terraform
terraform login

# 2. Generate backend_override.tf files for all workspace roots
./scripts/local-backend-setup.sh            # defaults to org "core-aws"
./scripts/local-backend-setup.sh my-org     # or specify your org
```

This creates a `backend_override.tf` in each workspace root. These files are gitignored (`*_override.tf`) and do not affect VCS-triggered runs.

### Running plan and apply

Use `TF_WORKSPACE` to target a specific workspace:

```bash
# Init (only needed once per workspace)
TF_WORKSPACE=test-client-dev-rds terraform -chdir=workspaces/rds init

# Plan
TF_WORKSPACE=test-client-dev-rds terraform -chdir=workspaces/rds plan

# Apply (HCP Terraform prompts for confirmation in your terminal)
TF_WORKSPACE=test-client-dev-rds terraform -chdir=workspaces/rds apply
```

### Workspace name reference

| Root | Example workspace name |
|---|---|
| `workspaces/api/` | `test-client-dev-api` |
| `workspaces/dns/` | `test-client-dev-dns` |
| `workspaces/lambda/` | `test-client-dev-lambda` |
| `workspaces/rds/` | `test-client-dev-rds` |
| `workspaces/vpc/` | `test-client-dev-vpc` |
| `workspaces/secure-baseline/` | `test-client-dev-secure-baseline` |
| `workspaces/account-portal/` | `test-client-dev` |
| `workspaces/account-bootstrap/` | `bootstrap-test-client-dev` |
| `bootstrap-accounts-dev/` | `bootstrap-account-workspace-management-dev` |
| `bootstrap-accounts-varset/` | `00-bootstrap-account-workspace-management` |

### Notes

- `backend_override.tf` files are gitignored — they never get committed or affect VCS runs
- Plans and applies run remotely in HCP Terraform with full OIDC credentials
- No local AWS keys needed
- The workspace must already exist in HCP Terraform (created by the control plane or portal)
- To validate syntax without a backend: `terraform -chdir=workspaces/rds validate` (requires `terraform init -backend=false` first)

---

## Related Documents

- [Agency-Orchestration-Platform-Spec.md](./Agency-Orchestration-Platform-Spec.md) — canonical architecture, phased roadmap, and completion status
- [Agency-AWS-Terraform-Framework-Spec.md](./Agency-AWS-Terraform-Framework-Spec.md) — full architecture spec
- [Agency-AWS-Terraform-Implementation-TODO.md](./Agency-AWS-Terraform-Implementation-TODO.md) — phase-by-phase build plan
- [Open-Source-Framework-Research.md](./Open-Source-Framework-Research.md) — open-source references for Phases 3-8
- [Terraform-Quick-Start.md](./Terraform-Quick-Start.md) — HCP Terraform workflow cheatsheet
- [docs/token-strategy.md](./docs/token-strategy.md) — HCP Terraform token types, placement, and team setup
