# Terraform Bootstrap Project - Quick Start Guide

This guide covers the active HCP Terraform workflow for the bootstrap workspace management project.

## Pre-Work Checklist

### 1. Authenticate to HCP Terraform

```bash
terraform login
```

This creates or refreshes your credentials for `app.terraform.io`.

### 2. Make sure required sensitive values exist in HCP Terraform

This control plane no longer uses OpenBao or Vault. Shared sensitive values should be managed through HCP Terraform variable sets.

At minimum, confirm the relevant workspaces have the inputs they need for:

- `aws_core_oauth_token_id`
- any optional control-plane sensitive variables managed by `bootstrap-accounts-varset/`

### 3. Choose the root you want to run

```text
hcp-bootstrap/               Creates the HCP Terraform control-plane workspaces
bootstrap-accounts-varset/    Shared HCP Terraform variable sets
bootstrap-accounts-dev/       Dev bootstrap workspace management
bootstrap-accounts-workbench/ Workbench bootstrap workspace management
```

## Typical Workflow

### Control-plane workspaces

```bash
cd hcp-bootstrap
terraform init
terraform plan
terraform apply
```

### Variable sets

```bash
cd bootstrap-accounts-varset
terraform init
terraform plan
terraform apply
```

### Development bootstrap workspaces

```bash
cd bootstrap-accounts-dev
terraform init
terraform plan
terraform apply
```

### Workbench bootstrap workspaces

```bash
cd bootstrap-accounts-workbench
terraform init
terraform plan
terraform apply
```

## Current Control-Plane Model

This project now manages bootstrap metadata directly in HCP Terraform:

- workspace names follow `bootstrap-<client_id>-<env>-<account_id>`
- workspace tags include client, environment, security tier, and service family
- workspace metadata is stored as Terraform variables on each workspace
- shared defaults are attached through HCP Terraform variable sets

## Account Metadata Shape

Each account entry in `accounts.tf.json` should include:

```json
{
  "123456789012": {
    "client_id": "acme",
    "account_name": "acme.dev",
    "env": "dev",
    "product_name": "platform",
    "region": "us-east-1",
    "security_tier": "standard",
    "services": ["bootstrap"]
  }
}
```

Optional fields:

- `service_family`
- `workspace_tags`
- `description`
- `working_directory`
- `vcs_repo_identifier`

## Common Issues

| Issue | Solution |
|-------|----------|
| Unauthorized to HCP Terraform | Run `terraform login` again |
| Variable-set IDs not found | Apply `bootstrap-accounts-varset/` before the environment roots |
| Missing VCS OAuth token ID | Set `aws_core_oauth_token_id` in the relevant HCP Terraform workspace |
| Planned workspace replacement after Phase 1 | Expected if old workspace names do not match the new naming convention |

## Additional Resources

- [README.md](./README.md)
- [Agency-AWS-Terraform-Framework-Spec.md](./Agency-AWS-Terraform-Framework-Spec.md)
- [Agency-AWS-Terraform-Implementation-TODO.md](./Agency-AWS-Terraform-Implementation-TODO.md)
