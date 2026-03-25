# core-tfe-bootstrap-workspace-management

Terraform control plane for managing HCP Terraform workspaces, projects, and variable sets across multiple clients and AWS accounts.

---

## Purpose

This repository is the **agency control plane**. It does not deploy AWS infrastructure directly — instead it provisions and configures the HCP Terraform workspaces that will deploy AWS infrastructure for each client.

When you add a client account to this repo and apply, HCP Terraform automatically gets:

- a workspace named `bootstrap-<client>-<env>` inside the correct project
- the right variable sets attached (global defaults + environment-specific + security-tier-specific)
- workspace metadata variables pre-populated (account ID, region, client ID, environment, security tier, selected services)
- failure notifications wired up
- optional service workspaces when you explicitly point an account at a service-workspace repo and provide the required service inputs

Every new account follows the same pattern with zero manual clicking in the HCP Terraform UI.

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
modules/                              # (Phase 5+) Reusable AWS service modules
  aws/
    account-bootstrap/
    secure-baseline/
    vpc/
    rds-secure/
    eks/
    s3-secure/
    iam-access/
workspaces/                           # (Phase 6+) Test per-service workspace roots
  vpc/
  rds/
  secure-baseline/
catalog/                              # DEPRECATED — being removed after Phase 7 validation
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
           │  For each account entry:     │
           │  - tfe_workspace             │
           │  - tfe_workspace_variable_set│
           │  - tfe_variable (metadata)   │
           │  - tfe_notification_config   │
           └──────────────────────────────┘
```

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
| `bootstrap-accounts-global` | all workspaces | `managed_by`, `workspace_class` |
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

#### One account or many — both are supported

The map key in `accounts.tf.json` is just a stable unique entry key. The actual AWS account ID lives in the `account_id` field. This means:

**One AWS account per environment (recommended for production clients):**
```
bootstrap-accounts-dev/accounts.tf.json       → "333333333333" (dedicated dev account)
bootstrap-accounts-workbench/accounts.tf.json → "222222222222" (dedicated workbench account)
```
Each environment is fully isolated — separate billing, separate IAM, separate blast radius.

**One AWS account shared across environments (fine for early-stage or single-account clients):**
```
bootstrap-accounts-dev/accounts.tf.json       → "889851937279" { "env": "dev" }
bootstrap-accounts-workbench/accounts.tf.json → "889851937279" { "env": "workbench" }
```
The same account ID appears in both roots. Two separate bootstrap workspaces are created (`bootstrap-<client>-dev` and `bootstrap-<client>-workbench`), each with its own variable sets and metadata — but both point at the same underlying AWS account. You can promote to separate accounts later by simply swapping in a new account ID.

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
        "security_tier": "standard",
        "services": ["account-bootstrap", "vpc", "rds"],
        "service_family": "platform",
        "vcs_repo_identifier": "your-org/your-repo"
      }
    }
  }
}
```

Commit and push to `main`. The HCP Terraform workspace picks up the change and creates the workspace automatically.

If you also want the control plane to create managed service workspaces, add `service_vcs_repo_identifier` plus the required `service_workspace_variables` for each service you want provisioned.

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
| `security_tier` | yes | `standard`, `high` | Controls which security-tier variable set is attached |
| `services` | no | default: `[]` | Desired services for this account. Stored as metadata and used to decide which managed service workspaces to create when service workspace management is enabled |
| `service_family` | no | any string, default: `platform` | Logical service grouping — used as a workspace tag |
| `vcs_repo_identifier` | yes | `org/repo` format | GitHub repo the workspace VCS integration points at |
| `service_vcs_repo_identifier` | no | `org/repo` format | Separate repo for managed service workspaces. If omitted, the control plane will not create service workspaces for this account |
| `service_workspace_variables` | no | map keyed by service name | Terraform variables to seed into each managed service workspace, for example network CIDRs for `vpc` |
| `working_directory` | no | default: `terraform` | Working directory inside the VCS repo for this workspace |
| `workspace_tags` | no | list of strings, default: `[]` | Additional HCP Terraform tags to apply to the workspace |

**Validation rules (enforced by Terraform `precondition` at plan time):**
- `account_id` must be a 12-digit AWS account ID
- `env` must be one of: `dev`, `qa`, `prod`, `workbench`, `sbx`
- `security_tier` must be one of: `standard`, `high`
- `client_id` or `product_name` must be non-empty
- `vcs_repo_identifier` must be set to a real repo — cannot be the default placeholder
- managed service workspaces require `service_vcs_repo_identifier`
- `vpc` requires `service_workspace_variables["vpc"].cidr_block`, `azs`, `private_subnets`, and `public_subnets`
- `rds` requires both `secure-baseline` and `vpc` in `services`

---

### `bootstrap-accounts-workbench/`

**Runs inside HCP Terraform** — workspace `bootstrap-account-workspace-management-workbench`.

Identical to `bootstrap-accounts-dev/` but targets the `bootstrap-workbench` project. Used for spike, prototyping, and client workbench accounts that are not tied to the dev lifecycle.

**How to add a workbench account:**

Edit `bootstrap-accounts-workbench/accounts.tf.json` using the same format as the dev accounts example, with `"env": "workbench"`.

If you only have one AWS account, use the same account ID here as in `bootstrap-accounts-dev/accounts.tf.json`. The `env` field distinguishes the workspaces — two separate bootstrap workspaces will be created in HCP Terraform, both pointing at the same AWS account.

---

### `bootstrap-accounts/` (shared module)

Not a root — called by `bootstrap-accounts-dev` and `bootstrap-accounts-workbench`. Do not apply directly.

**For each account entry it creates:**

1. **`tfe_workspace`** — named `bootstrap-<client_id>-<env>`
   - tagged with `bootstrap`, `workspace-class-bootstrap-account`, `client-<id>`, `env-<env>`, `tier-<tier>`, `family-<family>`
   - linked to VCS repo, points to the account's working directory
   - `auto_apply = true`, `execution_mode = remote`

2. **`tfe_workspace_variable_set`** — attaches up to 4 variable sets:
   - global (all workspaces)
   - environment-specific (matches `env` field)
   - security-tier-specific (matches `security_tier` field)
   - secrets (if configured)

3. **`tfe_variable`** — writes metadata directly into the workspace as Terraform variables:
   - `client_id`, `aws_account_id`, `aws_account_name`, `environment`, `aws_region`, `security_tier`, `service_family`, `selected_services`, `workspace_class`

4. **Optional `tfe_workspace` service workspaces** — created only when `service_vcs_repo_identifier` is set for the account
   - default service catalog in this repo: `secure-baseline`, `vpc`, `rds`
   - writes derived dependency variables like `secure_baseline_workspace_name` and `vpc_workspace_name`
   - writes service-specific bootstrap inputs from `service_workspace_variables`

5. **`tfe_notification_configuration`** — sends email on `run:errored` if notifications are enabled

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
4. If you want managed service workspaces too, also set `service_vcs_repo_identifier` and `service_workspace_variables`
5. Commit and push to `main`
6. HCP Terraform runs automatically and the workspace appears in the correct project

---

## Workspace Naming Convention

| Class | Pattern | Visible to client | Example |
|---|---|:---:|---|
| Control plane — varset | `00-bootstrap-account-workspace-management` | No | — |
| Control plane — env manager | `bootstrap-account-workspace-management-<env>` | No | `bootstrap-account-workspace-management-dev` |
| Bootstrap account | `bootstrap-<client_id>-<env>` | No | `bootstrap-acme-dev` |
| Account portal (Phase 7) | `<account_id>` | Yes | `123456789012` |
| Project (Phase 7, client self-service) | `<account_id>-<stack>` | Yes | `123456789012-vpc` |

The bootstrap layer is agency-internal. Clients log into HCP Terraform and see only their account-ID workspace. From there they self-service add project workspaces for their own stacks.

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

## Related Documents

- [Agency-AWS-Terraform-Framework-Spec.md](./Agency-AWS-Terraform-Framework-Spec.md) — full architecture spec
- [Agency-AWS-Terraform-Implementation-TODO.md](./Agency-AWS-Terraform-Implementation-TODO.md) — phase-by-phase build plan
- [Open-Source-Framework-Research.md](./Open-Source-Framework-Research.md) — open-source references for Phases 3-8
- [Terraform-Quick-Start.md](./Terraform-Quick-Start.md) — HCP Terraform workflow cheatsheet
