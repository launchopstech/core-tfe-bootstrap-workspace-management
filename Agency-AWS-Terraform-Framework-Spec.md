# Agency AWS Terraform Framework Spec

> Historical reference. The canonical architecture and phased roadmap now live in [Agency-Orchestration-Platform-Spec.md](./Agency-Orchestration-Platform-Spec.md).

## 1. Purpose

Build an agency-ready Terraform framework for AWS that can:

- onboard a new client with account, environment, and ownership metadata
- bootstrap Terraform Cloud workspaces, variable sets, and outputs from HCL
- apply a secure AWS baseline before workloads are deployed
- let each client enable only the services they need
- compose reusable AWS modules from metadata instead of one-off Terraform
- support repeatable delivery across dev, workbench, staging, and prod

This spec is tailored to the current repository. The repo already behaves like a control plane for Terraform Cloud workspace creation, shared variable sets, and notifications. The target state in this spec intentionally removes OpenBao or Vault from the design and uses HCL-managed Terraform Cloud resources instead.

## 2. What Already Exists In This Repo

The current repository already gives us a strong Phase 1 foundation:

- `bootstrap-accounts/` creates Terraform Cloud workspaces per account
- `bootstrap-accounts-dev/` and `bootstrap-accounts-workbench/` provide environment-specific entrypoints
- `bootstrap-accounts-varset/` manages shared Terraform Cloud variable sets
- the current code still contains Vault or OpenBao-era wiring that should be removed as part of the refactor
- `bootstrap-accounts-*/accounts.tf.json` already demonstrates metadata-driven account creation

Recommended direction:

- keep this repo as the Terraform Cloud control plane
- add an AWS runtime layer for secure account bootstrap and service deployment
- manage workspaces, variables, tags, and shared outputs directly in HCL
- avoid replacing the current pattern with raw S3 backends unless a client cannot use Terraform Cloud

## 3. Recommended Target Architecture

Use a two-layer model.

### Layer A: Control Plane

This repository remains responsible for:

- Terraform Cloud projects, workspaces, and variable sets
- workspace naming conventions and tags
- notifications and policy attachments
- Terraform Cloud workspace variables, tags, and outputs for shared metadata

### Layer B: AWS Runtime Platform

Add a new AWS runtime structure in this repository or a companion repo:

```text
bootstrap-accounts/
bootstrap-accounts-dev/
bootstrap-accounts-workbench/
bootstrap-accounts-varset/
catalog/
  clients/
    acme/
      client.yaml
  modules/
    aws/
      secure-baseline/
      account-bootstrap/
      vpc/
      eks/
      rds-secure/
      s3-secure/
      iam-access/
  stacks/
    acme/
      dev/
        main.tf
        variables.tf
        acme-dev.auto.tfvars.json
      prod/
        main.tf
        variables.tf
  scripts/
    render_metadata.py
    validate_metadata.py
  policies/
    sentinel/
    opa/
docs/
```

If you want the cleanest separation for agency operations, keep this repository as the control plane and create a second repository for `catalog/`. If you want speed for v1, keep both in one repo.

## 4. Public Repos To Study

Checked on March 13, 2026.

### Best-fit options

- `aws-ia/terraform-aws-control_tower_account_factory`
  - Link: https://github.com/aws-ia/terraform-aws-control_tower_account_factory
  - Best when you manage a client's AWS Organization with Control Tower and want account vending plus GitOps-style account requests.
  - Use it if your agency will own account creation for larger multi-account clients.

- `nozaq/terraform-aws-secure-baseline`
  - Link: https://github.com/nozaq/terraform-aws-secure-baseline
  - Best reference for secure account baselines aligned to CIS and AWS security best practices.
  - Use it as the model for your `secure-baseline` module, even if you wrap or selectively reimplement parts.

- `cloudposse/terraform-aws-components`
  - Link: https://github.com/cloudposse/terraform-aws-components
  - Best example of a service catalog made from opinionated Terraform root modules.
  - Useful when you want catalog-style building blocks instead of one giant root module.

- `cloudposse/atmos`
  - Link: https://github.com/cloudposse/atmos
  - Best example of metadata-driven stack orchestration with YAML-based environment composition.
  - Good reference even if you stay on vanilla Terraform and do not adopt Atmos.

- `terraform-aws-modules/terraform-aws-vpc`
  - Link: https://github.com/terraform-aws-modules/terraform-aws-vpc
  - Mature VPC module to wrap instead of building low-level networking from scratch.

- `terraform-aws-modules/terraform-aws-eks`
  - Link: https://github.com/terraform-aws-modules/terraform-aws-eks
  - Mature EKS module with current support for newer EKS features.

- `terraform-aws-modules/terraform-aws-rds`
  - Link: https://github.com/terraform-aws-modules/terraform-aws-rds
  - Strong base module for secure database wrappers.

### Recommended blend

For this repo and your agency model, the strongest blend is:

- current repo for Terraform Cloud workspace control plane
- `nozaq/terraform-aws-secure-baseline` as the design reference for security controls
- `terraform-aws-modules/*` as the engine under thin agency-owned wrappers
- `cloudposse/atmos` as inspiration for metadata composition, not necessarily as a mandatory dependency
- `aws-ia/terraform-aws-control_tower_account_factory` only when the client has or wants Control Tower

## 5. Core Design Principles

- secure by default, exception by approval
- one metadata model drives workspaces, variables, and deployed services
- modules expose business-friendly inputs while hiding low-level AWS complexity
- clients can adopt a subset of services without forking the platform
- state and execution are isolated by client and environment
- every client deployment is reproducible from versioned metadata

## 6. Metadata Model

Start with a human-friendly YAML source and generate Terraform-friendly JSON from it.

### Source metadata

`catalog/clients/acme/client.yaml`

```yaml
client_id: acme
client_name: Acme Corp
tfc:
  organization: agency-platform
  project_name: acme-platform
aws:
  management_account_id: "111111111111"
  accounts:
    - name: workbench
      account_id: "222222222222"
      env: workbench
      region: us-east-1
    - name: dev
      account_id: "333333333333"
      env: dev
      region: us-east-1
    - name: prod
      account_id: "444444444444"
      env: prod
      region: us-east-1
security_tier: high
contacts:
  engineering_owner: platform@acme.example
  billing_owner: finance@acme.example
environments:
  - name: dev
    region: us-east-1
    services:
      - vpc
      - eks
      - rds
    vpc:
      cidr_block: 10.20.0.0/16
      azs: [us-east-1a, us-east-1b, us-east-1c]
      private_subnets: [10.20.1.0/24, 10.20.2.0/24, 10.20.3.0/24]
      public_subnets: [10.20.11.0/24, 10.20.12.0/24, 10.20.13.0/24]
    eks:
      cluster_name: acme-dev
      kubernetes_version: "1.33"
    rds:
      engine: postgres
      engine_version: "16.4"
      instance_class: db.t4g.large
      allocated_storage: 100
  - name: prod
    region: us-east-1
    services:
      - vpc
      - eks
      - s3
      - rds
tags:
  ManagedBy: terraform
  PlatformOwner: agency
```

### Generated environment tfvars

`catalog/stacks/acme/dev/acme-dev.auto.tfvars.json`

```json
{
  "client_id": "acme",
  "environment": "dev",
  "region": "us-east-1",
  "security_tier": "high",
  "services": ["vpc", "eks", "rds"],
  "terraform_role_arn": "arn:aws:iam::333333333333:role/TerraformDeployRole",
  "tags": {
    "ManagedBy": "terraform",
    "PlatformOwner": "agency"
  },
  "vpc_config": {
    "cidr_block": "10.20.0.0/16",
    "azs": ["us-east-1a", "us-east-1b", "us-east-1c"],
    "private_subnets": ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"],
    "public_subnets": ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]
  },
  "eks_config": {
    "cluster_name": "acme-dev",
    "kubernetes_version": "1.33"
  },
  "rds_config": {
    "engine": "postgres",
    "engine_version": "16.4",
    "instance_class": "db.t4g.large",
    "allocated_storage": 100
  }
}
```

### Extend the current repo seed format

Your current `accounts.tf.json` pattern can evolve into richer workspace metadata:

```json
{
  "locals": {
    "accounts": {
      "333333333333": {
        "client_id": "acme",
        "account_name": "acme.dev",
        "env": "dev",
        "product_name": "platform",
        "region": "us-east-1",
        "security_tier": "high",
        "services": ["vpc", "eks", "rds"]
      }
    }
  }
}
```

## 7. Terraform Cloud Strategy

Because this repository already manages Terraform Cloud workspaces, the default strategy should be:

- use Terraform Cloud as the primary backend and execution engine
- create separate workspaces per client and environment
- attach shared variable sets by environment and security tier
- keep metadata in HCL, Terraform Cloud variables, workspace tags, and workspace outputs
- do not depend on OpenBao or Vault for this framework

Recommended isolation model:

- v1: one Terraform Cloud organization for the agency, one project per client
- regulated clients: separate Terraform Cloud organization per client

Naming convention:

- control plane workspace: `bootstrap-account-workspace-management-<env>`
- client bootstrap workspace: `bootstrap-<client>-<env>-<account_id>`
- runtime workspace: `aws-<client>-<env>-<stack>`

Sample Terraform Cloud workspace extension:

```hcl
resource "tfe_workspace" "runtime_stack" {
  for_each = local.runtime_workspaces

  name              = "aws-${each.value.client_id}-${each.value.env}-${each.value.stack}"
  description       = "AWS runtime stack for ${each.value.client_id} ${each.value.env} ${each.value.stack}"
  organization      = var.tfc_organization
  project_id        = each.value.project_id
  working_directory = "catalog/stacks/${each.value.client_id}/${each.value.env}"
  execution_mode    = "remote"
  terraform_version = var.terraform_version
  auto_apply        = false
  tag_names         = ["aws", each.value.client_id, each.value.env, each.value.stack]

  vcs_repo {
    identifier     = var.vcs_repository_identifier
    branch         = "main"
    oauth_token_id = var.vcs_oauth_token_id
  }
}
```

## 8. Phase Plan

### Phase 1 - Control Plane Hardening

Goal: turn the current workspace factory into a reusable agency control plane using Terraform Cloud only.

Tasks:

- standardize workspace naming for bootstrap and runtime stacks
- expand `accounts.tf.json` or generated inputs to include client, region, and service metadata
- create Terraform Cloud projects per client
- create shared variable sets per environment and security tier
- remove Vault or OpenBao provider usage from the control plane
- replace external metadata storage with Terraform Cloud variables, tags, and outputs
- add workspace tags for client, env, and service family

Deliverables:

- stable naming convention
- project and variable-set model
- metadata schema v1
- control-plane design with no OpenBao dependency

### Phase 2 - Client Intake And Metadata Pipeline

Goal: take client account details and desired services as data.

Tasks:

- define YAML schema for client, accounts, environments, services, and contacts
- validate required fields and allowed service names
- generate `.auto.tfvars.json` files for each environment
- generate workspace manifests for the control plane
- optionally generate onboarding checklists for the agency team

Sample metadata rendering script:

```python
import json
import pathlib
import sys
import yaml

source = pathlib.Path(sys.argv[1])
doc = yaml.safe_load(source.read_text())

for env in doc["environments"]:
    payload = {
        "client_id": doc["client_id"],
        "environment": env["name"],
        "region": env["region"],
        "security_tier": doc["security_tier"],
        "services": env["services"],
        "tags": doc["tags"],
    }

    if "vpc" in env:
        payload["vpc_config"] = env["vpc"]
    if "eks" in env:
        payload["eks_config"] = env["eks"]
    if "rds" in env:
        payload["rds_config"] = env["rds"]

    target = pathlib.Path("catalog/stacks") / doc["client_id"] / env["name"] / f'{doc["client_id"]}-{env["name"]}.auto.tfvars.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, indent=2) + "\n")
```

Exit criteria:

- one command can validate and render all client environment inputs

### Phase 3 - AWS Account Bootstrap

Goal: create the minimum secure deploy path into each client AWS account.

Tasks:

- create cross-account `TerraformDeployRole` in each client account
- require `sts:ExternalId` in the trust policy
- decide whether account vending is done by your repo or by AWS Control Tower AFT
- create or integrate with KMS keys for logs and workload encryption
- enable organization access if you manage AWS Organizations
- define break-glass and support access policy

Sample cross-account role:

```hcl
data "aws_iam_policy_document" "terraform_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.agency_principal_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

resource "aws_iam_role" "terraform_deploy" {
  name               = "TerraformDeployRole"
  assume_role_policy = data.aws_iam_policy_document.terraform_assume_role.json
}
```

Exit criteria:

- Terraform Cloud workspace can assume a role into the target client account and run `plan`

### Phase 4 - Secure Baseline

Goal: deploy security controls before service modules.

Tasks:

- create `modules/aws/secure-baseline`
- enable CloudTrail, AWS Config, GuardDuty, Security Hub, IAM Access Analyzer, and log encryption
- enforce S3 block public access and secure bucket policies
- create KMS keys with rotation and least-privilege policies
- add account-level detective controls and security notifications
- make optional controls explicit instead of disabled by accident

Sample baseline wrapper:

```hcl
module "secure_baseline" {
  source = "../../modules/aws/secure-baseline"

  client_id          = var.client_id
  environment        = var.environment
  region             = var.region
  security_tier      = var.security_tier
  enable_guardduty   = true
  enable_securityhub = true
  enable_config      = true
  tags               = var.tags
}
```

Exit criteria:

- a new account reaches the agreed baseline before any application stack is applied

### Phase 5 - Service Catalog Modules

Goal: publish reusable modules for common AWS services.

Initial module set:

- `vpc`
- `eks`
- `rds-secure`
- `s3-secure`
- `iam-access`
- `cloudwatch-observability`
- `backup-baseline`

Tasks:

- wrap upstream modules behind agency-owned interfaces
- set secure defaults such as encryption, private networking, retention, and tagging
- publish examples and READMEs for each module
- add contract tests and linting for each module

Sample secure RDS wrapper:

```hcl
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.13"

  identifier                         = var.identifier
  engine                             = var.engine
  engine_version                     = var.engine_version
  instance_class                     = var.instance_class
  allocated_storage                  = var.allocated_storage
  manage_master_user_password        = true
  storage_encrypted                  = true
  kms_key_id                         = var.kms_key_id
  iam_database_authentication_enabled = true
  deletion_protection                = true
  backup_retention_period            = max(var.backup_retention_period, 14)
  copy_tags_to_snapshot              = true
  publicly_accessible                = false
  multi_az                           = var.multi_az
  subnet_ids                         = var.subnet_ids
  vpc_security_group_ids             = var.security_group_ids
  tags                               = var.tags
}
```

Exit criteria:

- at least three service modules can be consumed without editing module source code

### Phase 6 - Metadata-Driven Composition

Goal: let client metadata choose which services are deployed in each environment.

Tasks:

- create one stack per client and environment
- always deploy `secure-baseline`
- conditionally deploy services from `var.services`
- validate service dependencies, such as `eks` requiring `vpc`
- emit outputs that later stacks can consume

Sample environment stack:

```hcl
terraform {
  cloud {
    organization = var.tfc_organization
    workspaces {
      name = var.workspace_name
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn    = var.terraform_role_arn
    external_id = var.external_id
  }
}

locals {
  enable_vpc = contains(var.services, "vpc")
  enable_eks = contains(var.services, "eks")
  enable_rds = contains(var.services, "rds")
}

module "secure_baseline" {
  source         = "../../../modules/aws/secure-baseline"
  client_id      = var.client_id
  environment    = var.environment
  region         = var.region
  security_tier  = var.security_tier
  tags           = var.tags
}

module "vpc" {
  source = "../../../modules/aws/vpc"
  count  = local.enable_vpc ? 1 : 0

  name            = "${var.client_id}-${var.environment}"
  cidr_block      = var.vpc_config.cidr_block
  azs             = var.vpc_config.azs
  public_subnets  = var.vpc_config.public_subnets
  private_subnets = var.vpc_config.private_subnets
  tags            = var.tags
}

module "eks" {
  source = "../../../modules/aws/eks"
  count  = local.enable_eks ? 1 : 0

  cluster_name       = var.eks_config.cluster_name
  kubernetes_version = var.eks_config.kubernetes_version
  vpc_id             = module.vpc[0].vpc_id
  subnet_ids         = module.vpc[0].private_subnet_ids
  tags               = var.tags
}

module "rds" {
  source = "../../../modules/aws/rds-secure"
  count  = local.enable_rds ? 1 : 0

  identifier        = "${var.client_id}-${var.environment}-db"
  engine            = var.rds_config.engine
  engine_version    = var.rds_config.engine_version
  instance_class    = var.rds_config.instance_class
  allocated_storage = var.rds_config.allocated_storage
  subnet_ids        = module.vpc[0].database_subnet_ids
  security_group_ids = [module.vpc[0].db_security_group_id]
  tags              = var.tags
}
```

Exit criteria:

- adding or removing a service is a metadata change, not a new handwritten stack

### Phase 7 - Workspace Orchestration For Projects And Orgs

Goal: after account and baseline setup, create workspaces for client platform stacks and optional project stacks.

Tasks:

- create one runtime workspace per client environment stack
- optionally create app-team workspaces for tenant-specific layers
- attach the right variable sets to the right workspace classes
- expose workspace IDs and stack metadata through Terraform Cloud outputs and tags
- support org-level and project-level patterns

Recommended workspace classes:

- `bootstrap-account`
- `platform-baseline`
- `platform-services`
- `application`

Exit criteria:

- workspaces are generated from metadata and do not require manual UI creation

### Phase 8 - Delivery, Policy, And Operations

Goal: make the platform supportable for an agency, not just deployable once.

Tasks:

- add CI for `fmt`, `validate`, `tflint`, and `tfsec` or `checkov`
- add policy checks using Sentinel or OPA for forbidden patterns
- run drift detection on a schedule
- define versioning for modules and client stacks
- build upgrade playbooks for provider and module major versions
- define onboarding and offboarding runbooks
- log every plan and apply through Terraform Cloud notifications

Exit criteria:

- every client stack can be validated, planned, approved, and audited consistently

## 9. Security Baseline Requirements

These should be default expectations for a "highly secure" offering:

- cross-account deploy role with `ExternalId`
- no long-lived IAM users for automation
- Terraform Cloud variable sets for inputs and sensitive values
- CloudTrail enabled and protected
- AWS Config enabled
- GuardDuty enabled
- Security Hub enabled where supported
- encrypted logs and data at rest with KMS
- S3 public access blocked by default
- VPC endpoints for sensitive services when justified
- default private subnets for databases and cluster nodes
- deletion protection on critical data services
- backups and retention enabled by policy

## 10. Recommended MVP Scope

Start smaller than the full catalog.

MVP service set:

- account-bootstrap
- secure-baseline
- vpc
- s3-secure
- rds-secure
- eks

MVP environments:

- workbench
- dev
- prod

MVP decisions:

- Terraform Cloud for state and execution
- one project per client
- one runtime stack per client environment
- thin wrappers around upstream modules
- no OpenBao or Vault dependency

## 11. Key Decisions To Make Early

- Will the agency manage client AWS Organizations or only member accounts?
- Will regulated clients require separate Terraform Cloud organizations?
- Will you support only Terraform Cloud, or also S3 backends?
- Will service modules be fully custom, or wrappers over upstream modules?
- Will app teams get their own workspaces, or will the agency run all applies centrally?

## 12. Suggested Execution Order

1. Extend the current workspace metadata model and naming conventions.
2. Add client YAML and the metadata render/validate scripts.
3. Create `account-bootstrap` and `secure-baseline` modules.
4. Build `vpc`, `s3-secure`, and `rds-secure` wrappers.
5. Build the first environment stack using metadata-driven composition.
6. Add runtime workspace creation to the current control plane.
7. Add CI, policy checks, and runbooks.

## 13. Final Recommendation

Do not throw away the current repository design. It already solves a hard part of an agency platform: workspace factory, shared variables, metadata persistence, and environment-specific bootstrap entrypoints.

The right next move is to refactor this repository into a Terraform Cloud HCL-only control plane and build an AWS runtime catalog beside it. That gives you:

- a reusable agency onboarding flow
- secure-by-default AWS deployments
- modular service selection per client
- a path to scale from a single client to many clients without duplicating Terraform
