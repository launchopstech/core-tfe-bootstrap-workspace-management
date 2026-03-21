# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repo is a Terraform control plane for managing HCP Terraform (app.terraform.io) workspaces and shared infrastructure metadata across AWS accounts. It is **not** a standard app codebase — there are no build systems or test frameworks. The "code" is Terraform HCL and Python metadata scripts.

## Execution Order (Critical)

These Terraform roots must be applied in dependency order. Each root runs inside an HCP Terraform workspace — not locally — after the first step.

1. **`hcp-bootstrap/`** — Creates the control-plane workspaces in HCP Terraform. Run locally with `terraform login` first.
2. **`bootstrap-accounts-varset/`** — Creates HCP Terraform projects and shared variable sets. Depends on step 1.
3. **`bootstrap-accounts-dev/`** and **`bootstrap-accounts-workbench/`** — Creates account-level bootstrap workspaces per environment. Depends on step 2.

```bash
# Step 1 — run locally
terraform login  # authenticate to app.terraform.io
cd hcp-bootstrap && terraform init && terraform plan && terraform apply

# Steps 2-3 — triggered via HCP Terraform (remote execution)
cd ../bootstrap-accounts-varset && terraform init && terraform apply
cd ../bootstrap-accounts-dev && terraform init && terraform apply
cd ../bootstrap-accounts-workbench && terraform init && terraform apply
```

## Metadata Pipeline Commands

```bash
# Validate a client YAML file
python3 catalog/scripts/validate_metadata.py catalog/clients/<client_id>/client.yaml

# Generate tfvars and workspace manifests from client YAML
python3 catalog/scripts/render_metadata.py catalog/clients/<client_id>/client.yaml
```

Generated outputs land in `catalog/stacks/<client_id>/` (tfvars) and `catalog/workspaces/<client_id>/` (runtime workspace manifests). These are auto-generated — edit the source YAML, not the outputs.

## Architecture

### Two-Layer Model

- **Control Plane (this repo)**: Manages HCP Terraform workspaces, projects, variable sets, and account metadata
- **Bootstrap Workspaces (created by this repo)**: Per-account orchestration workspaces that provision runtime infrastructure

### Terraform Root Roles

| Root | HCP Workspace | Purpose |
|------|--------------|---------|
| `hcp-bootstrap/` | local | Creates the 3 control-plane workspaces |
| `bootstrap-accounts-varset/` | `00-bootstrap-account-workspace-management` | Creates 5 HCP projects + shared variable sets |
| `bootstrap-accounts-dev/` | `bootstrap-account-workspace-management-dev` | Creates bootstrap workspaces for dev accounts |
| `bootstrap-accounts-workbench/` | `bootstrap-account-workspace-management-workbench` | Creates bootstrap workspaces for workbench accounts |

### Shared Module

`bootstrap-accounts/` is a reusable module sourced by `bootstrap-accounts-dev/` and `bootstrap-accounts-workbench/`. It creates `tfe_workspace`, `tfe_workspace_variable_set`, and `tfe_variable` resources for each account entry.

### Account Metadata (`accounts.tf.json`)

Each environment root (`bootstrap-accounts-dev/`, `bootstrap-accounts-workbench/`) has an `accounts.tf.json` file defining which AWS accounts to bootstrap:

```json
{
  "locals": {
    "accounts": {
      "<12-digit-account-id>": {
        "client_id": "string",
        "account_name": "string",
        "env": "dev|qa|prod|workbench",
        "product_name": "string",
        "region": "aws-region",
        "security_tier": "standard|high",
        "services": ["service-list"],
        "service_family": "string",
        "vcs_repo_identifier": "org/repo"
      }
    }
  }
}
```

To add a new account, add an entry here and apply the corresponding root.

### Catalog / Metadata Pipeline

`catalog/clients/<client_id>/client.yaml` is the source of truth for client onboarding. The Python pipeline in `catalog/scripts/` validates and renders it into:
- Per-environment tfvars: `catalog/stacks/<client_id>/<env>/<client_id>-<env>.auto.tfvars.json`
- Runtime workspace manifests: `catalog/workspaces/<client_id>/runtime-workspaces.json`

Allowed services: `account-bootstrap`, `secure-baseline`, `vpc`, `eks`, `rds`, `s3`, `iam-access`
Service dependency rule: `eks` and `rds` require `vpc`.

### Variable Set Hierarchy

Variable sets are created in `bootstrap-accounts-varset/` and attached to workspaces by the bootstrap module. Hierarchy: global defaults → environment-specific → security-tier-specific. Workspace IDs are passed between roots via `data.tfe_outputs`.

## Requirements

- Terraform >= 1.0, HCP Terraform provider >= 0.49.0
- Python 3.7+ (PyYAML preferred; falls back to Ruby YAML parser if unavailable)
- HCP Terraform account with VCS OAuth token configured
