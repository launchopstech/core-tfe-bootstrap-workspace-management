# core-tfe-bootstrap-workspace-management

Terraform control plane for bootstrap workspace management in HCP Terraform.

## What It Does

- creates bootstrap workspaces for AWS accounts in `app.terraform.io`
- applies a standardized naming and tagging model to each workspace
- stores workspace metadata in HCP Terraform variables and outputs
- manages shared variable sets for environment defaults, security tiers, and optional sensitive control-plane values

## Active Roots

- `hcp-bootstrap/` creates the HCP Terraform control-plane workspaces
- `bootstrap-accounts-varset/` manages shared HCP Terraform variable sets
- `bootstrap-accounts-dev/` manages bootstrap workspaces for the dev project
- `bootstrap-accounts-workbench/` manages bootstrap workspaces for the workbench project

## Quick Start

```bash
terraform login
cd hcp-bootstrap
terraform init
terraform plan

cd ../bootstrap-accounts-varset
terraform init
terraform plan

cd ../bootstrap-accounts-dev
terraform init
terraform plan
```

See [Terraform-Quick-Start.md](./Terraform-Quick-Start.md) for the current HCP Terraform workflow.
