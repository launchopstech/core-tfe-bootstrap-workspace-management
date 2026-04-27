# HCP Terraform Token Strategy

This document describes every authentication token used by the platform, where it is configured, and what permissions it requires.

## Token Types

| Token Type | Scope | Created In | Purpose |
|---|---|---|---|
| **User token** | Personal | HCP Terraform → User Settings → Tokens | Local CLI operations, one-time bootstrap (`hcp-bootstrap/`) |
| **Organization token** | Org-wide | HCP Terraform → Settings → API Tokens → Organization | Full org access — avoid using in workspaces unless necessary |
| **Team token** | Team-scoped | HCP Terraform → Settings → Teams → \<team\> → Token | Scoped workspace/project access for automation |
| **VCS OAuth token** | VCS connection | HCP Terraform → Settings → Version Control → Providers | Allows HCP Terraform to read Git repos for workspace VCS integration |

## Token Placement Map

### Layer 1: One-Time Bootstrap (Local CLI)

| Where | Token | How Set | Notes |
|---|---|---|---|
| `terraform login` | **User token** | Interactive login, stored in `~/.terraform.d/credentials.tfrc.json` | Used only once to run `hcp-bootstrap/`. Must have org-level admin permissions to create workspaces and projects. |

### Layer 2: Control Plane Workspaces

These workspaces manage other workspaces. They use the **TFE provider** and need tokens that can create/modify workspaces, variable sets, and projects.

| Workspace | Variable | Token Type | Category | Sensitive | Permission Required |
|---|---|---|---|---|---|
| `00-bootstrap-account-workspace-management` | (default runner) | Workspace token (auto) | — | — | Only reads/writes variable sets within its own project. Default runner token is sufficient. |
| `bootstrap-account-workspace-management-dev` | (default runner) | Workspace token (auto) | — | — | Creates workspaces in `bootstrap-dev` and `team-dev` projects. **If the default runner token lacks cross-project permission, set `TFE_TOKEN` as env var using a team token.** |
| `bootstrap-account-workspace-management-workbench` | (default runner) | Workspace token (auto) | — | — | Same as above for `bootstrap-workbench` and `team-workbench`. |

### Layer 3: Account Portal Workspaces

These are workspace factories — they create child deployer workspaces using the TFE provider.

| Workspace | Variable | Token Type | Category | Sensitive | Permission Required |
|---|---|---|---|---|---|
| `test-client-dev` | `TFE_TOKEN` | **Team token** | `env` | Yes | **Manage Workspaces** on the `team-dev` project. Must be able to create workspaces, set variables, attach variable sets, and configure notifications. |
| `test-client-workbench` | `TFE_TOKEN` | **Team token** | `env` | Yes | Same, scoped to `team-workbench` project. |
| *(every account-portal workspace)* | `TFE_TOKEN` | **Team token** | `env` | Yes | Scoped to the corresponding `team-<env>` project. |

### Layer 4: Runtime Deployer Workspaces (AWS)

These workspaces deploy actual infrastructure. They authenticate to AWS via OIDC, not tokens.

| Workspace | Variable | Token Type | Category | Sensitive | Permission Required |
|---|---|---|---|---|---|
| `test-client-dev-secure-baseline` | `TFC_AWS_PROVIDER_AUTH` | String `"true"` | `env` | No | Enables OIDC dynamic credentials |
| `test-client-dev-secure-baseline` | `TFC_AWS_RUN_ROLE_ARN` | IAM role ARN | `env` | No | ARN of `TerraformDeployRole` in the target AWS account |
| `test-client-dev-vpc` | Same OIDC pair | Same | `env` | No | Same — injected automatically by the account portal |
| `test-client-dev-rds` | Same OIDC pair | Same | `env` | No | Same |

**No HCP Terraform API tokens are needed on runtime deployer workspaces.** They only talk to AWS.

### VCS OAuth Token

| Where Used | Variable | How Set | Notes |
|---|---|---|---|
| `hcp-bootstrap/` | `vcs_oauth_token_id` | Terraform variable (set once during bootstrap) | Connects HCP Terraform to your GitHub/GitLab org |
| `bootstrap-accounts/` | `aws_core_oauth_token_id` | Terraform variable (passed from env root) | Same OAuth connection — used when creating workspace VCS repo links |
| `workspaces/account-portal/` | `project_vcs_oauth_token_id` | Workspace variable (injected by control plane) | Same OAuth connection — portal passes it to child deployer workspaces |

**All three reference the same VCS OAuth connection.** It is created once in HCP Terraform Settings → Version Control → Providers.

> **Updating the OAuth token ID** (e.g. after a GitHub org migration or VCS provider re-creation): the `ot-...` token ID must be updated in both `hcp-bootstrap/terraform.tfvars` **and** the `aws_core_oauth_token_id` workspace variable on `bootstrap-account-workspace-management-dev` and `bootstrap-account-workspace-management-workbench`. The workspace variable is **not managed by Terraform** — update it via the HCP Terraform UI or API. See `docs/runbooks/github-org-migration.md` for the full procedure.

## Recommended Team Setup

### `platform-automation` Team

Create a dedicated team for automation tokens:

1. **HCP Terraform** → **Settings** → **Teams** → **Create team**
2. Name: `platform-automation`
3. **Project access**: Add each `team-<env>` project with **Admin** permission (needed to create workspaces)
4. Generate a **Team token** from the team settings page
5. Set this token as `TFE_TOKEN` on all account-portal workspaces

### Permission Matrix

| Team | `bootstrap-*` projects | `team-*` projects | Used By |
|---|---|---|---|
| `platform-automation` | Admin | Admin | Account-portal workspaces (`TFE_TOKEN` env var) |
| `owners` | Admin | Admin | Agency operators (user tokens for local CLI) |
| `<client>-admin` | No access | Read + Write on assigned project | Client team (see portal workspaces, trigger applies) |

## How Tokens Flow Through the System

```
Local operator (user token)
  └─ hcp-bootstrap/
       └─ creates 3 control-plane workspaces
            ├─ 00-bootstrap-account-workspace-management
            │    └─ default runner token (sufficient)
            │    └─ creates projects + variable sets
            │
            ├─ bootstrap-account-workspace-management-dev
            │    └─ default runner token (or TFE_TOKEN if cross-project)
            │    └─ creates bootstrap + portal + agency-deployer workspaces
            │    └─ injects TFE_TOKEN on portal workspaces? (see automation note)
            │
            └─ bootstrap-account-workspace-management-workbench
                 └─ same as dev

Portal workspace (team token via TFE_TOKEN)
  └─ test-client-dev
       └─ reads project_requests_json
       └─ creates test-client-dev-vpc, test-client-dev-rds
       └─ injects OIDC env vars on child workspaces

Runtime deployer (OIDC — no HCP token needed)
  └─ test-client-dev-vpc
       └─ authenticates to AWS via TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN
       └─ deploys VPC resources
```

## Automating TFE_TOKEN Injection

Currently `TFE_TOKEN` must be set manually on each account-portal workspace. To automate this:

### Option A: Variable Set (Recommended)

1. Create a variable set named `portal-automation-token`
2. Add `TFE_TOKEN` as a sensitive env variable with the `platform-automation` team token
3. Attach the variable set to all `team-*` projects
4. All portal workspaces automatically inherit the token

### Option B: Control Plane Injection

Add a `tfe_variable` resource in `bootstrap-accounts/workspace-variables.tf` that sets `TFE_TOKEN` on the portal (team) workspaces. Requires storing the team token as a sensitive Terraform variable on the control-plane workspace.

### Option C: Per-Workspace (Current)

Manually set `TFE_TOKEN` on each portal workspace via the API or UI. Does not scale.

**Recommendation**: Use Option A (variable set) for simplicity and consistency.

## Security Notes

- **Never commit tokens** to `accounts.tf.json` or any `.tf` file
- **Rotate tokens** periodically and after any accidental exposure
- **Scope tokens tightly** — use team tokens scoped to specific projects, not org tokens
- **Mark all tokens as sensitive** in HCP Terraform variables
- Runtime deployer workspaces use **OIDC dynamic credentials** — no long-lived AWS keys
- The `TerraformDeployRole` trust policy scopes OIDC access by org, project, and workspace name pattern
