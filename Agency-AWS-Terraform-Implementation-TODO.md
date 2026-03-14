# Agency AWS Terraform Implementation TODO

This checklist converts the framework spec into an execution plan.

Successful completion means we can onboard a client, generate environment inputs, and run Terraform from the command line for a selected client environment.

## Final Definition Of Done

At the end of all phases, this flow works from the command line:

```bash
terraform login
python3 catalog/scripts/validate_metadata.py catalog/clients/acme/client.yaml
python3 catalog/scripts/render_metadata.py catalog/clients/acme/client.yaml
cd catalog/stacks/acme/dev
terraform init
terraform plan
terraform apply
```

If Terraform Cloud remote execution is kept, the same CLI flow should still trigger the remote run successfully.

## Phase 1 - Control Plane Hardening

Goal: make the current Terraform Cloud workspace factory reusable for multiple clients without OpenBao or Vault.

### TODO

- [x] define a standard naming convention for all workspace classes
- [x] define tags for `client_id`, `env`, `service_family`, and `security_tier`
- [x] extend the current account seed model to include `client_id`, `region`, `security_tier`, and `services`
- [x] create a Terraform Cloud project strategy
- [x] define shared variable sets by environment and by security tier
- [x] remove the `vault` provider and Vault resources from the control-plane code
- [x] remove Vault-related variables from modules and environment entrypoints
- [x] replace external metadata storage with Terraform Cloud workspace tags, variables, and outputs
- [x] document how runtime workspaces differ from bootstrap workspaces
- [x] add a README section describing the Terraform Cloud HCL-only control-plane architecture

### Deliverables

- [x] updated metadata model for `accounts.tf.json` or generated equivalent
- [x] workspace naming standard
- [x] variable-set attachment model
- [x] refactored control-plane module with no Vault dependency

### Success Criteria

- [x] bootstrap workspaces can still be created from the current repo structure
- [x] the control-plane Terraform no longer requires OpenBao or Vault credentials
- [x] a new client can be represented without editing core module logic

## Phase 2 - Client Intake And Metadata Pipeline

Goal: treat client onboarding as structured data instead of manual edits.

### TODO

- [ ] create `catalog/clients/<client>/client.yaml` schema
- [ ] define required keys for client, accounts, environments, contacts, and tags
- [ ] define allowed service names and dependency rules
- [ ] create `catalog/scripts/validate_metadata.py`
- [ ] create `catalog/scripts/render_metadata.py`
- [ ] generate `.auto.tfvars.json` per client environment
- [ ] generate workspace input manifests for runtime stack creation
- [ ] add sample client metadata for one reference customer
- [ ] add usage docs for validate and render commands

### Deliverables

- [ ] metadata schema v1
- [ ] validation script
- [ ] rendering script
- [ ] sample generated `tfvars.json`

### Success Criteria

- [ ] invalid metadata fails fast with clear error messages
- [ ] valid metadata produces deterministic outputs
- [ ] one command can render all Terraform inputs for a client

## Phase 3 - AWS Account Bootstrap

Goal: prepare each client AWS account for secure Terraform access.

### TODO

- [ ] create `catalog/modules/aws/account-bootstrap`
- [ ] create deploy role `TerraformDeployRole` with cross-account trust
- [ ] require `sts:ExternalId` in trust policies
- [ ] define least-privilege baseline permissions for Terraform
- [ ] define management-account or agency principal ARN inputs
- [ ] define KMS strategy for logs and secrets
- [ ] decide whether AWS Organizations and Control Tower are in scope
- [ ] document manual prerequisites for client-owned accounts
- [ ] add outputs for role ARN and bootstrap artifacts

### Deliverables

- [ ] account-bootstrap module
- [ ] example bootstrap stack
- [ ] trust policy example
- [ ] onboarding runbook for client accounts

### Success Criteria

- [ ] Terraform can assume the deploy role into a target account
- [ ] `terraform plan` succeeds against the target AWS account from CLI

## Phase 4 - Secure Baseline

Goal: enforce account-level security controls before service deployment.

### TODO

- [ ] create `catalog/modules/aws/secure-baseline`
- [ ] enable CloudTrail
- [ ] enable AWS Config
- [ ] enable GuardDuty
- [ ] enable Security Hub where applicable
- [ ] enable IAM Access Analyzer
- [ ] create encrypted logging buckets and KMS keys
- [ ] block public access for all baseline S3 buckets
- [ ] add baseline outputs required by downstream modules
- [ ] document baseline feature flags and defaults

### Deliverables

- [ ] secure-baseline module
- [ ] module README
- [ ] example stack usage
- [ ] outputs contract for downstream services

### Success Criteria

- [ ] a new environment can apply baseline resources cleanly
- [ ] baseline outputs are consumable by service modules

## Phase 5 - Service Catalog Modules

Goal: provide reusable, secure building blocks for AWS services.

### TODO

- [ ] create `catalog/modules/aws/vpc`
- [ ] create `catalog/modules/aws/eks`
- [ ] create `catalog/modules/aws/rds-secure`
- [ ] create `catalog/modules/aws/s3-secure`
- [ ] create `catalog/modules/aws/iam-access`
- [ ] decide which modules wrap upstream community modules
- [ ] standardize tagging and naming across all modules
- [ ] enforce secure defaults in each module
- [ ] create `variables.tf`, `outputs.tf`, and `README.md` for each module
- [ ] add usage examples for each module

### Deliverables

- [ ] initial module catalog
- [ ] secure defaults documented
- [ ] examples for each module

### Success Criteria

- [ ] at least `vpc`, `rds-secure`, and `s3-secure` can be consumed without source edits
- [ ] all modules expose stable outputs needed by environment stacks

## Phase 6 - Metadata-Driven Composition

Goal: choose services per environment from metadata.

### TODO

- [ ] create `catalog/stacks/<client>/<env>/main.tf`
- [ ] create `catalog/stacks/<client>/<env>/variables.tf`
- [ ] wire AWS provider with `assume_role`
- [ ] always deploy `secure-baseline`
- [ ] conditionally deploy selected service modules from `var.services`
- [ ] validate service dependency rules such as `eks -> vpc`
- [ ] expose outputs for later stacks and app teams
- [ ] document required inputs for each environment stack
- [ ] add at least one full example stack for `dev`

### Deliverables

- [ ] runtime environment stack template
- [ ] conditional service composition
- [ ] example client environment stack

### Success Criteria

- [ ] adding a service is a metadata change only
- [ ] `terraform plan` succeeds for one complete example environment

## Phase 7 - Workspace Orchestration

Goal: generate runtime Terraform Cloud workspaces for platform stacks and optional app stacks.

### TODO

- [ ] extend control-plane Terraform to create runtime workspaces
- [ ] attach correct variable sets to runtime workspaces
- [ ] define workspace classes such as `platform-baseline`, `platform-services`, and `application`
- [ ] expose runtime workspace IDs through Terraform Cloud outputs or directly through `tfe_workspace` references
- [ ] define working directory strategy for runtime stacks
- [ ] define VCS repo strategy for runtime stacks
- [ ] add tagging standards for runtime workspaces
- [ ] document how a new client gets bootstrap and runtime workspaces

### Deliverables

- [ ] runtime workspace factory
- [ ] runtime variable-set model
- [ ] workspace metadata available from Terraform Cloud HCL, tags, and outputs

### Success Criteria

- [ ] runtime workspaces can be created from metadata
- [ ] CLI-triggered Terraform runs target the expected workspace

## Phase 8 - CI, Policy, And Operations

Goal: make the platform supportable and auditable.

### TODO

- [ ] add CI for `terraform fmt -check`
- [ ] add CI for `terraform validate`
- [ ] add `tflint`
- [ ] add `tfsec` or `checkov`
- [ ] add policy checks with Sentinel or OPA
- [ ] add drift-detection workflow
- [ ] add module versioning and release process
- [ ] add upgrade playbooks for providers and modules
- [ ] add onboarding runbook
- [ ] add incident and break-glass runbook
- [ ] add offboarding runbook

### Deliverables

- [ ] CI pipeline
- [ ] policy checks
- [ ] operational runbooks

### Success Criteria

- [ ] every stack is validated before apply
- [ ] security regressions are caught before merge
- [ ] operators can run the platform without tribal knowledge

## Phase 9 - MVP Acceptance Test

Goal: prove the framework works end to end.

### TODO

- [ ] create one sample client such as `acme`
- [ ] create environments `workbench`, `dev`, and `prod`
- [ ] render metadata into generated Terraform inputs
- [x] create bootstrap workspace for at least one AWS account
- [ ] create runtime workspace for at least one environment stack
- [ ] apply `account-bootstrap`
- [ ] apply `secure-baseline`
- [ ] apply one service stack with `vpc`
- [ ] apply one data service stack such as `rds-secure`
- [ ] capture outputs and document expected state

### Acceptance Commands

```bash
terraform login
python3 catalog/scripts/validate_metadata.py catalog/clients/acme/client.yaml
python3 catalog/scripts/render_metadata.py catalog/clients/acme/client.yaml
cd catalog/stacks/acme/dev
terraform init
terraform plan
terraform apply
```

### Final Success Criteria

- [ ] the commands above complete successfully
- [ ] Terraform can run from the command line for a chosen client and environment
- [ ] the selected AWS resources are created using metadata-driven module selection
- [ ] no manual edits are required between metadata render and Terraform apply

## Recommended Build Order

- [ ] complete Phase 1 first
- [ ] complete Phase 2 next
- [ ] complete Phase 3 and Phase 4 before building most service modules
- [ ] complete Phase 5 and Phase 6 together
- [ ] complete Phase 7 after one working runtime stack exists
- [ ] complete Phase 8 before onboarding real client workloads
- [ ] complete Phase 9 as the release gate for v1
