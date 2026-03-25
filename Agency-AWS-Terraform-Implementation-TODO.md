# Agency AWS Terraform Implementation TODO

> Historical reference. The canonical architecture and phased roadmap now live in [Agency-Orchestration-Platform-Spec.md](./Agency-Orchestration-Platform-Spec.md).

This checklist converts the framework spec into an execution plan.

Successful completion means we can onboard a client by editing one JSON file, have HCP Terraform automatically provision their workspaces, and have the client self-service deploy their own services from their account-portal workspace.

## Final Definition Of Done

At the end of all phases, onboarding a new client account works like this:

**Step 1 — Agency adds the account (one JSON edit):**
```json
// bootstrap-accounts-dev/accounts.tf.json
{
  "locals": {
    "accounts": {
      "333333333333": {
        "client_id": "acme",
        "account_name": "acme.dev",
        "env": "dev",
        "region": "us-east-1",
        "security_tier": "standard",
        "services": ["vpc", "rds"],
        "vcs_repo_identifier": "org/repo"
      }
    }
  }
}
```

**Step 2 — Push to main. HCP Terraform automatically:**
- creates bootstrap workspace `bootstrap-acme-dev-333333333333` (hidden from client)
- creates account-portal workspace `333333333333` (client-facing)
- attaches correct variable sets and pre-populates workspace variables
- runs account-bootstrap and secure-baseline in the client AWS account

**Step 3 — Client logs into HCP Terraform and sees only `333333333333`:**
- adds a `333333333333-vpc` project workspace
- adds a `333333333333-rds` project workspace
- each workspace runs the corresponding service module against their AWS account

No Python pipeline. No YAML files. No manual clicking in the HCP Terraform UI.

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

~~Goal: treat client onboarding as structured data instead of manual edits.~~

**Superseded.** The `catalog/` pipeline (client.yaml → Python scripts → stacks/) was built for a monolithic per-environment workspace model that has been replaced by the per-service account-portal model. The deliverables below were completed but are no longer the target approach.

**New model:** `accounts.tf.json` in each environment root is the only metadata file. No Python scripts, no YAML, no generated stacks. See the updated Definition of Done above.

**`catalog/` directory is retired.** The `catalog/` folder and its contents (clients/, scripts/, stacks/, workspaces/, schema/) should be removed once Phase 7 is validated. Keeping it during transition only.

### Completed (now superseded)

- [x] create `catalog/clients/<client>/client.yaml` schema
- [x] define required keys for client, accounts, environments, contacts, and tags
- [x] define allowed service names and dependency rules
- [x] create `catalog/scripts/validate_metadata.py`
- [x] create `catalog/scripts/render_metadata.py`
- [x] generate `.auto.tfvars.json` per client environment
- [x] generate workspace input manifests for runtime stack creation
- [x] add sample client metadata for one reference customer
- [x] add usage docs for validate and render commands

### Replacement TODOs

- [x] remove `catalog/` directory after Phase 7 is validated
- [x] document `accounts.tf.json` schema with all supported fields and defaults
- [x] add validation directly in the bootstrap module (Terraform `precondition` blocks for required fields, allowed env values, allowed security_tier values)

## Open-Source Reference Frameworks

See `Open-Source-Framework-Research.md` for full evaluation. Summary:

| Framework | Match | Use For |
|-----------|-------|---------|
| Cloud Posse + Atmos | ~60% | Phases 3-8 AWS module sources (wrap, don't fork) |
| MCAF Landing Zone | ~55% | Phase 4 secure baseline reference |
| AWS AFT | ~50% | Phase 3 account provisioning pattern reference |
| Gruntwork/Terragrunt | ~45% | Phase 6 multi-account stack structure reference |
| alexbasista/tfe-workspacer | high | Phase 7 runtime workspace factory — wrap instead of extending bespoke code |
| scalefactory/tfe-workspaces | high | Phase 7 reference architecture (HashiCorp case study) |
| aws-ia/tfe-workspace-orchestrator | high | Phase 7 JSON map → for_each pattern — closest to accounts.tf.json |

**Strategy for AWS modules (Phases 3-8)**: source `modules/aws/<service>` from Cloud Posse components (pin version, add opinionated defaults). Modules live at repo root `modules/`, not inside `catalog/`.

**Strategy for TFC control plane (Phase 7)**: wrap `alexbasista/terraform-tfe-workspacer` for account-portal and project workspaces rather than extending the current bespoke `bootstrap-accounts/` module. The current module is original and correct; the upstream modules add VCS, team access, and notification handling needed for the account-portal layer.

---

## Phase 3 - AWS Account Bootstrap

Goal: prepare each client AWS account for secure Terraform access.

**Reference**: `cloudposse/terraform-aws-account-map`, `cloudposse/terraform-aws-iam-role`; AFT account request pattern for cross-account IAM bootstrapping.

### TODO

- [x] create `modules/aws/account-bootstrap`
- [x] create deploy role `TerraformDeployRole` with cross-account trust
- [x] require `sts:ExternalId` in trust policies
- [x] define least-privilege baseline permissions for Terraform
- [x] add permissions boundary to `TerraformDeployRole` to prevent privilege escalation
- [x] enforce no long-lived IAM users for automation (service accounts use roles only)
- [x] define management-account or agency principal ARN inputs
- [x] define KMS strategy for logs and secrets
- [x] define break-glass and support access policy for agency team
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

**Reference**: `cloudposse/terraform-aws-security-hub`, `cloudposse/terraform-aws-guardduty`, `cloudposse/terraform-aws-cloudtrail`, `cloudposse/terraform-aws-config`; MCAF Landing Zone for Account Vending Machine + baseline pattern.

### TODO

- [x] create `modules/aws/secure-baseline`
- [x] enable CloudTrail
- [x] enable AWS Config
- [x] enable GuardDuty
- [x] enable Security Hub where applicable
- [x] enable IAM Access Analyzer
- [x] create KMS keys with automatic rotation and least-privilege key policies
- [x] create encrypted logging buckets using KMS keys
- [x] block public access for all baseline S3 buckets
- [x] add secure bucket policies (deny non-SSL, deny non-encrypted puts)
- [x] add account-level security event notifications (SNS/email for GuardDuty findings and Config non-compliance)
- [x] add baseline outputs required by downstream modules
- [ ] document baseline feature flags and defaults — make optional controls explicit (not silently disabled)

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

**Reference**: `cloudposse/terraform-aws-vpc`, `cloudposse/terraform-aws-eks`, `cloudposse/terraform-aws-rds-cluster`, `cloudposse/terraform-aws-s3-bucket`. Wrap these as thin opinionated modules rather than building from scratch.

### TODO

- [x] create `modules/aws/vpc` (wrap `terraform-aws-modules/terraform-aws-vpc`)
- [ ] create `modules/aws/eks` (wrap `terraform-aws-modules/terraform-aws-eks`)
- [x] create `modules/aws/rds-secure` (wrap `terraform-aws-modules/terraform-aws-rds`)
- [x] create `modules/aws/s3-secure`
- [ ] create `modules/aws/iam-access`
- [ ] create `modules/aws/cloudwatch-observability`
- [ ] create `modules/aws/backup-baseline`
- [ ] decide which modules wrap upstream community modules vs built from scratch
- [ ] standardize tagging and naming across all modules
- [ ] enforce secure defaults in each module (encryption, private networking, deletion protection, backup retention)
- [ ] create `variables.tf`, `outputs.tf`, and `README.md` for each module
- [ ] add usage examples for each module
- [ ] add `terraform validate` contract test for each module in CI

### Deliverables

- [ ] initial module catalog
- [ ] secure defaults documented
- [ ] examples for each module

### Success Criteria

- [ ] at least `vpc`, `rds-secure`, and `s3-secure` can be consumed without source edits
- [ ] all modules expose stable outputs needed by environment stacks

## Phase 6 - Per-Service Workspace Model

Goal: each AWS service (vpc, rds, eks, etc.) runs in its own project workspace, consuming variables pre-set by the control plane. No monolithic stacks, no generated tfvars files.

**How it works:**
- The account-portal workspace (Phase 7) carries all shared variables: `aws_account_id`, `region`, `terraform_role_arn`, `security_tier`, `client_id`, `environment`
- Each project workspace (`<account_id>-vpc`, `<account_id>-rds`) inherits these via variable set attachment
- Service-specific config (VPC CIDRs, RDS instance class, EKS version) is set as workspace variables when the agency provisions the project workspace, or by the client directly
- Each service module (`modules/aws/vpc`, `modules/aws/rds-secure`) is a standalone Terraform root — no composition layer needed

**Reference**: `modules/aws/<service>` from Phase 5; variable set hierarchy from Phase 1.

### TODO

**Per-service workspace Terraform roots:**
- [x] create `workspaces/vpc/main.tf` — standalone VPC workspace root using `modules/aws/vpc`
- [x] create `workspaces/rds/main.tf` — standalone RDS workspace root using `modules/aws/rds-secure`
- [ ] create `workspaces/eks/main.tf` — standalone EKS workspace root using `modules/aws/eks`
- [ ] create `workspaces/s3/main.tf` — standalone S3 workspace root using `modules/aws/s3-secure`
- [x] create `workspaces/secure-baseline/main.tf` — secure baseline workspace root (always provisioned by agency, not client)

**Provider and variable wiring:**
- [ ] wire AWS provider `assume_role` + `external_id` in each workspace root — values come from inherited workspace variables
- [ ] add HCP Terraform backend block in each workspace root — `organization` and `workspace_name` from environment variables
- [ ] define `variables.tf` for each workspace root covering only service-specific inputs
- [ ] validate service dependency rules at apply time (eks workspace requires vpc workspace output)

**Control plane extension (feeds into Phase 7):**
- [ ] extend `bootstrap-accounts/` module to set `selected_services` workspace variable on account-portal workspace
- [ ] document which workspace variables are agency-set vs client-set

**Documentation:**
- [ ] add `workspaces/README.md` explaining the per-service workspace model
- [ ] add example variable values for each workspace root
- [ ] document cross-workspace output consumption (e.g. EKS workspace reads VPC IDs from `tfe_outputs` of VPC workspace)

### Deliverables

- [ ] `workspaces/` directory with one root per service
- [ ] each workspace root is independently deployable with correct workspace variables
- [ ] cross-workspace output wiring documented

### Success Criteria

- [ ] adding a service = client adds one new project workspace pointing at the correct `workspaces/<service>/` root
- [ ] no tfvars files are generated or committed
- [ ] `terraform plan` succeeds in a VPC workspace for a dev account using only inherited workspace variables

## Phase 7 - Workspace Orchestration

Goal: provision client-facing account workspaces from the bootstrap layer, then let clients self-service add project workspaces from within their account workspace.

**Reference**: `alexbasista/terraform-tfe-workspacer` + `terraform-tfe-projecter` for runtime workspace factory primitives (team access, VCS, notifications, variable set attachment); `scalefactory/terraform-tfe-workspaces` as reference architecture (HashiCorp case study backed); `aws-ia/terraform-tfe-workspace-orchestrator` for nested JSON map → `for_each` pattern. See `Open-Source-Framework-Research.md` for full comparison.

### Two-Layer Workspace Model

This is the intended end state:

```
Agency-internal (hidden from client)         Client-facing (client logs in here)
────────────────────────────────────         ──────────────────────────────────
bootstrap-<client>-<env>-<account_id>   →    <account_id>
  managed by this repo                          named by AWS account ID
  wires variable sets, IAM, baseline            client sees only this workspace
  client never touches this                     client adds project workspaces here
                                                e.g. vpc-stack, app-stack, rds-stack
```

The bootstrap workspace is the **machine room**. The account-ID workspace is the **door the client walks through**. The client self-services project workspaces from the account-ID workspace — they do not need to know the bootstrap layer exists.

### Workspace Classes

| Class | Name pattern | Managed by | Visible to client |
|-------|-------------|------------|:-----------------:|
| `bootstrap-account` | `bootstrap-<client>-<env>-<account_id>` | this repo | No |
| `account-portal` | `<account_id>` | this repo (provisioned, then handed off) | Yes |
| `project` | `<account_id>-<stack>` | client (self-service) | Yes |

### TODO

**Bootstrap → account-portal handoff:**
- [ ] extend bootstrap module to create the account-portal workspace named by AWS account ID
- [ ] attach correct variable sets to the account-portal workspace (same hierarchy as bootstrap: global + env + tier)
- [ ] pre-populate account-portal workspace variables: `aws_account_id`, `region`, `client_id`, `environment`, `terraform_role_arn`, `security_tier`
- [ ] grant client team access to the account-portal workspace (read plan, apply with approval)
- [ ] deny client team access to the bootstrap workspace (agency-only)
- [ ] set `auto_apply = false` on account-portal workspaces — all applies require approval

**Account-portal workspace setup:**
- [ ] define the account-portal workspace as the VCS root where client project workspaces are declared
- [ ] define a project workspace manifest format clients use to register a new project (YAML or JSON in their VCS repo)
- [ ] document the self-service flow: client adds a project manifest → account-portal workspace applies → new project workspace appears

**Naming and tagging:**
- [ ] account-portal workspace name = AWS account ID (`<account_id>`)
- [ ] project workspace name = `<account_id>-<stack>` (e.g. `333333333333-vpc`, `333333333333-app`)
- [ ] tag account-portal workspaces: `workspace-class-account-portal`, `client-<id>`, `env-<env>`, `tier-<tier>`
- [ ] tag project workspaces: `workspace-class-project`, `client-<id>`, `env-<env>`, `stack-<name>`

**Outputs and metadata:**
- [ ] expose account-portal workspace IDs as outputs from `bootstrap-accounts-dev` and `bootstrap-accounts-workbench`
- [ ] configure run notifications on account-portal workspaces (Slack or email on errored runs)
- [ ] document how a new client moves from bootstrap → account-portal → first project workspace

### Deliverables

- [ ] account-portal workspace factory (extension of bootstrap module)
- [ ] client team access model (bootstrap hidden, account-portal visible)
- [ ] project workspace self-service pattern and manifest format
- [ ] client onboarding handoff runbook

### Success Criteria

- [ ] client can log into HCP Terraform and see only their account-ID workspace
- [ ] client can add a project workspace without agency intervention
- [ ] bootstrap workspaces are not visible to the client team
- [ ] all project workspaces inherit the correct variable sets and IAM role from the account-portal layer

## Phase 8 - CI, Policy, And Operations

Goal: make the platform supportable and auditable.

**Reference**: Atmos GitHub Actions workflows; tflint/tfsec are built-in to the Cloud Posse component library CI patterns.

### TODO

- [ ] add CI for `terraform fmt -check`
- [ ] add CI for `terraform validate`
- [ ] add `tflint`
- [ ] add `tfsec` or `checkov`
- [ ] add policy checks with Sentinel or OPA
- [ ] add drift-detection workflow
- [ ] define module versioning and release process (semver tags per module)
- [ ] define client-stack module version pinning strategy (which module version each client stack uses)
- [ ] add upgrade playbooks for providers and modules
- [ ] add onboarding runbook
- [ ] add incident and break-glass runbook
- [ ] add offboarding runbook
- [ ] log and audit every plan and apply via Terraform Cloud notifications

### Deliverables

- [ ] CI pipeline
- [ ] policy checks
- [ ] operational runbooks

### Success Criteria

- [ ] every stack is validated before apply
- [ ] security regressions are caught before merge
- [ ] operators can run the platform without tribal knowledge

## Phase 9 - MVP Acceptance Test

Goal: prove the full flow works end to end — from a JSON edit to a client self-servicing their first AWS service.

### TODO

- [ ] add one real client account entry to `bootstrap-accounts-dev/accounts.tf.json`
- [x] create bootstrap workspace for at least one AWS account
- [ ] create account-portal workspace for that account (visible to client)
- [ ] apply `account-bootstrap` module against the client AWS account
- [ ] apply `secure-baseline` module against the client AWS account
- [ ] client adds a `<account_id>-vpc` project workspace and triggers a plan
- [ ] client adds a `<account_id>-rds` project workspace and triggers a plan
- [ ] capture workspace outputs and document expected state

### Acceptance Flow

```
1. Agency edits bootstrap-accounts-dev/accounts.tf.json
2. Push to main → HCP Terraform auto-applies → bootstrap + account-portal workspaces created
3. Agency triggers account-bootstrap workspace run → TerraformDeployRole created in client AWS account
4. Agency triggers secure-baseline workspace run → CloudTrail, GuardDuty, Config enabled
5. Client logs into HCP Terraform → sees only workspace named by their account ID
6. Client clicks "New Workspace" → points at workspaces/vpc/ → triggers plan → apply
7. VPC exists in client AWS account
```

### Final Success Criteria

- [ ] agency onboards a client by editing one JSON file and pushing to main
- [ ] client sees only their account-ID workspace — no bootstrap internals visible
- [ ] client self-services a VPC without agency intervention after handoff
- [ ] no Python scripts, no YAML pipeline, no generated tfvars files involved

## Key Architectural Decisions (Resolve Before Phase 3)

These decisions from the spec (section 11) must be made before certain phases start. Deferring them creates rework.

- [ ] **Org ownership**: will the agency manage client AWS Organizations or only member accounts? (affects Phase 3 scope)
- [ ] **Regulated client isolation**: will regulated clients require a separate Terraform Cloud organization, or is project-level isolation sufficient? (affects Phase 7 design)
- [ ] **Backend strategy**: support only Terraform Cloud, or also S3 backends for clients that cannot use TFC? (deferred to Phase 10 — per-service workspace model is TFC-native)
- [ ] **Module strategy**: wrap upstream modules (`terraform-aws-modules/*`) or build from scratch? (affects Phase 5 scope; current recommendation: wrap)
- [ ] **App-team autonomy**: will app teams get their own workspaces for tenant-specific layers, or does the agency run all applies centrally? (affects Phase 7 workspace class design)

---

## Phase 10 - Deferred / Later Phase

Items that are in scope long-term but intentionally excluded from v1. Tracked here so they are not lost.

### Not Supported In v1

- [ ] **Regulated client TFC isolation**: separate Terraform Cloud organization per regulated client — architectural change requiring org-level provider config and cross-org module sharing
- [ ] **S3 backend support**: alternative Terraform backend for clients that cannot use Terraform Cloud — requires parallel stack template without `cloud {}` block
- [ ] **AWS Organizations account vending**: agency-owned account creation via AWS Organizations / Control Tower AFT — requires management account access and Control Tower setup
- [ ] **App-team self-service workspaces**: tenant teams create their own workspaces against a shared platform layer — requires workspace template + RBAC design
- [ ] **VPC endpoints for sensitive services**: SSM, S3, ECR, Secrets Manager VPC endpoints as optional security control — referenced in spec security baseline section 9
- [ ] **Multi-region per client environment**: single client environment spanning multiple AWS regions — current model is single-region per environment
- [ ] **Sentinel or OPA policy library for regulated tiers**: full policy-as-code library for `security_tier = high` clients — Phase 8 adds the CI hook but not the full library
- [ ] **`cloudwatch-observability` module full implementation**: cross-account observability, log aggregation, and dashboards — Phase 5 creates the stub but full cross-account pattern is deferred
- [ ] **`backup-baseline` module full implementation**: AWS Backup plans, vaults, and cross-account backup copies — Phase 5 creates the stub but cross-account backup is deferred
- [ ] **Atmos adoption**: no longer relevant — `catalog/` pipeline is retired; Atmos solves a problem this model no longer has

### Success Criteria

- [ ] all deferred items are explicitly documented with the reason they were deferred
- [ ] Phase 10 items do not block v1 release (Phase 9 acceptance test passes without them)

---

## Recommended Build Order

- [x] complete Phase 1 first
- [x] complete Phase 2 next
- [ ] resolve Key Architectural Decisions before starting Phase 3
- [ ] complete Phase 3 and Phase 4 before building most service modules
- [ ] complete Phase 5 and Phase 6 together
- [ ] complete Phase 7 after one working runtime stack exists
- [ ] complete Phase 8 before onboarding real client workloads
- [ ] complete Phase 9 as the release gate for v1
- [ ] revisit Phase 10 items for v2 planning after v1 ships
