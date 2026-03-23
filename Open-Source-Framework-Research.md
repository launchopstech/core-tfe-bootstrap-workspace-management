# Open-Source Agency Model AWS Infrastructure Frameworks

Research conducted 2026-03-19 to find open-source projects that accelerate Phases 3-8 of this repo.

## Tier 1 — Best Fit (60%+ match)

### 1. Cloud Posse + Atmos (~60% match)

- **Component library**: https://github.com/cloudposse-terraform-components/aws-components
- **Orchestrator**: https://github.com/cloudposse/atmos
- **Atmos docs**: https://atmos.tools
- **Atmos + HCP Terraform**: https://atmos.tools/integrations/terraform-cloud

**What it gives you:**
- 200+ opinionated AWS Terraform root modules (VPC, EKS, RDS, S3, IAM, security baselines)
- Atmos YAML manifest files per environment/component — conceptually identical to this repo's `catalog/clients/acme/client.yaml` approach
- Multi-account component inheritance with stack configs
- HCP Terraform + Spacelift integration via Atmos workflows
- Pre-built security components: `terraform-aws-security-hub`, `terraform-aws-guardduty`, `terraform-aws-cloudtrail`, `terraform-aws-config`

**Gap**: Not designed for external multi-client billing isolation; Atmos is more team/environment oriented than client-oriented.

**Phase mapping:**

| This Repo Phase | Cloud Posse / Atmos Component |
|-----------------|-------------------------------|
| Phase 3: Account Bootstrap | `cloudposse/terraform-aws-account-map`, `cloudposse/terraform-aws-iam-role` |
| Phase 4: Secure Baseline | `cloudposse/terraform-aws-security-hub`, `cloudposse/terraform-aws-guardduty`, `cloudposse/terraform-aws-cloudtrail`, `cloudposse/terraform-aws-config` |
| Phase 5: Service Catalog | `cloudposse/terraform-aws-vpc`, `cloudposse/terraform-aws-eks`, `cloudposse/terraform-aws-rds-cluster`, `cloudposse/terraform-aws-s3-bucket` |
| Phase 6: Metadata Composition | Atmos `stacks/*.yaml` — drop-in for `catalog/stacks/<client>/<env>/*.tfvars.json` |
| Phase 7: Workspace Orchestration | Atmos workflows + HCP Terraform integration |
| Phase 8: CI/CD + Policy | Atmos GitHub Actions workflows, tflint/tfsec built-in |

---

### 2. AWS Control Tower Account Factory for Terraform — AFT (~50% match)

- **Repo**: https://github.com/aws-ia/terraform-aws-control_tower_account_factory

**What it gives you:**
- GitOps-based, metadata-driven AWS account provisioning (account request YAML → new AWS account)
- Account-level customizations repo pattern (runs Terraform after account is created)
- Handles cross-account IAM bootstrapping automatically
- CI/CD pipeline per account included

**Gap**: Requires AWS Control Tower (management account); not HCP Terraform native; no service catalog for workloads.

---

### 3. Schuberg Philis MCAF Landing Zone (~55% match)

- **Repo**: https://github.com/schubergphilis/terraform-aws-mcaf-landing-zone

**What it gives you:**
- "Account Vending Machine" pattern — Terraform module that creates accounts + baselines
- Security baseline built-in: CloudTrail, Config, GuardDuty, Security Hub
- Native HCP Terraform modules (pure Terraform, no CDK)
- Per-account IAM roles and SSO integration

**Gap**: Single-org focused; no service catalog for workloads; no metadata pipeline.

---

## Tier 2 — Useful for Specific Phases

### 4. Gruntwork / Terragrunt reference architecture (~45% match)

- **Repo**: https://github.com/gruntwork-io/terragrunt-infrastructure-live-example

**What it gives you:** Best-practice DRY multi-account folder structure (account → region → env → module); widely adopted pattern.

**Gap**: Not HCP Terraform native; no agency/multi-client concept; requires Gruntwork subscription for module library.

### 5. AWS Landing Zone Accelerator (LZA) (~30% match)

- **Repo**: https://github.com/awslabs/landing-zone-accelerator-on-aws

**What it gives you:** Enterprise-grade YAML-driven multi-account governance, 35+ security service configs.

**Gap**: CDK/CloudFormation-based, not Terraform; single-org; heavyweight.

---

## TFC Workspace Control Plane — Existing Open-Source Repos

Researched 2026-03-20. These specifically implement the `tfe` provider workspace factory pattern (what this repo's `bootstrap-accounts/` module does).

### 1. `aws-ia/terraform-tfe-workspace-orchestrator` — strongest structural match

- **Repo**: https://github.com/aws-ia/terraform-tfe-workspace-orchestrator
- **Registry**: https://registry.terraform.io/modules/aws-ia/workspace-orchestrator/tfe/latest

Takes a nested map input that maps directly to `jsondecode(file("workspaces.json"))` — essentially the `accounts.tf.json` pattern. Creates `tfe_workspace`, `tfe_variable`, and `tfe_workspace_variable_set` in one root with `for_each`. Has a `shared_variable_set_ids` key that is conceptually identical to this repo's variable set attachment model.

### 2. `scalefactory/terraform-tfe-workspaces` — best reference architecture

- **Repo**: https://github.com/scalefactory/terraform-tfe-workspaces
- **Registry**: https://registry.terraform.io/modules/scalefactory/workspaces/tfe/latest
- **HashiCorp case study**: https://www.hashicorp.com/en/resources/managing-workspaces-with-the-tfe-provider-at-scale-factory

A self-managing control-plane workspace that provisions all other workspaces — exactly this repo's pattern. HashiCorp published a case study on it. Config is passed as HCL variable maps (JSON-compatible via `jsondecode`).

### 3. `alexbasista/terraform-tfe-workspacer` + `terraform-tfe-projecter` — most composable

- **Workspace module**: https://github.com/alexbasista/terraform-tfe-workspacer
- **Project module**: https://github.com/alexbasista/terraform-tfe-projecter
- **Registry**: https://registry.terraform.io/modules/alexbasista/workspacer/tfe/latest

Split into two modules (workspace factory + project factory), mirroring this repo's `bootstrap-accounts/` shared module + `bootstrap-accounts-varset/` separation. Handles team access, VCS, notifications, and variable set attachment. Designed to be called with `for_each` over a metadata map.

### Comparison

| Repo | tfe_workspace | tfe_project | tfe_variable_set | JSON/metadata-driven |
|------|:---:|:---:|:---:|:---:|
| aws-ia/workspace-orchestrator | Yes | Partial | Yes (by ID) | Yes — native |
| scalefactory/tfe-workspaces | Yes | Likely | Yes | HCL map (JSON-compatible) |
| alexbasista/tfe-workspacer | Yes | Via companion | Yes (by name) | for_each over map |

---

## Bottom Line

**The control-plane workspace factory in this repo (`bootstrap-accounts/` module) is original work — no open-source project does the full pattern.** The multi-client YAML intake pipeline, environment-tier variable set hierarchy, and cross-workspace `tfe_outputs` chaining are not replicated elsewhere.

However, the workspace/project/variable-set factory primitives are reinvented. The `aws-ia/terraform-tfe-workspace-orchestrator` and `scalefactory/terraform-tfe-workspaces` modules cover the same ground as `bootstrap-accounts/` with broader VCS, team access, and notification support.

## Recommendations

1. **Phase 7 (runtime workspace creation)**: refactor or replace `bootstrap-accounts/` to wrap `alexbasista/terraform-tfe-workspacer` — it handles team access, VCS, notifications, and variable set attachment that will be needed for runtime workspaces and is already well-tested.

2. **Immediate**: read the Scale Factory case study and compare their workspace map structure against `accounts.tf.json` — high likelihood their module can replace or validate the current `bootstrap-accounts/` implementation with no logic change.

3. **Phases 3-8 AWS modules**: adopt Cloud Posse components as upstream wrapping targets in `catalog/modules/aws/<service>` — pin a version, add opinionated defaults for this repo's security tier and tagging conventions.

4. **Phase 4 secure baseline**: use `nozaq/terraform-aws-secure-baseline` (referenced in the spec) as the design reference alongside Cloud Posse security components.

5. **Do not adopt Atmos as a dependency** until Phase 6 composition is validated in plain Terraform — use it as a design reference only.
