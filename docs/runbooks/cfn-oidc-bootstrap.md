# Runbook: CloudFormation OIDC Bootstrap (`cfn-terraform-bootstrap.yaml`)

Deploy the one-time AWS prerequisite stack that creates the OIDC provider and `TerraformDeployRole` so HCP Terraform workspaces can authenticate to an AWS account via dynamic credentials (no long-lived keys).

Without this stack, every service workspace (`vpc`, `rds`, `api`, `secure-baseline`, etc.) will fail with:
```
Error: No valid credential sources found
AssumeRoleWithWebIdentity 403 AccessDenied
```

---

## Template location

```
bootstrap/cfn-terraform-bootstrap.yaml
```

This is a **generic, parameterized template** — not client-specific. The same file is reused for every account, deployed with different parameter values. It supports **unlimited clients per account** with no template changes required per onboarding.

---

## What the stack creates

| Resource | Name | Purpose |
|---|---|---|
| `AWS::IAM::OIDCProvider` | `app.terraform.io` | Federates HCP Terraform as a trusted OIDC issuer |
| `AWS::IAM::ManagedPolicy` | `TerraformDeployPolicy` | Least-privilege permissions across ~15 AWS service areas |
| `AWS::IAM::Role` | `TerraformDeployRole` | Assumed by any workspace in the configured HCP projects |
| `AWS::KMS::Key` | — | Platform encryption key for CloudTrail, Config, RDS, Secrets Manager |
| `AWS::KMS::Alias` | `alias/<KMSAliasName>` | Alias for the KMS key |

---

## Trust model — project-scoped (not per-client)

The trust policy trusts **all workspaces in the configured HCP Terraform projects**, not individual client workspace name patterns:

```
organization:core-aws:project:bootstrap-dev:workspace:*:run_phase:*
organization:core-aws:project:team-dev:workspace:*:run_phase:*
```

**Why this scales:** Adding a new client requires zero changes to this stack. The trust boundary is enforced by HCP Terraform project access — only workspaces the agency places in `bootstrap-dev` or `team-dev` can assume the role.

> **Previous design (retired 2026-04-26):** The template used to scope trust to per-client workspace name patterns via `ClientId` and `AdditionalClientId` parameters. This broke when two clients shared the same AWS account because a second `TerraformDeployRole` could not be created. The project-scoped design replaces this entirely.

---

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `HCPOrganization` | No | `core-aws` | HCP Terraform org name |
| `HCPBootstrapProject` | Yes | — | HCP project for bootstrap workspaces (e.g. `bootstrap-dev`) |
| `HCPTeamProject` | Yes | — | HCP project for team/service workspaces (e.g. `team-dev`) |
| `KMSAliasName` | Yes | — | KMS alias (e.g. `alias/dev-shared-platform`) |
| `ExistingOIDCProviderArn` | No | `""` | ARN of existing OIDC provider — **set this if the provider already exists** |

---

## Step 0 — Run the pre-flight check (always)

Before deploying the CFN stack for any new client, run the pre-flight check to detect conflicts automatically:

```bash
# Authenticate to the target AWS account first, then:
./bootstrap/pre-flight-check.sh \
  --client-id <client-id> \
  --env <env>
```

The script checks all 6 singleton resources and prints:
- Whether each resource already exists
- The exact `enable_*` overrides to add to the client's secure-baseline config
- The `ExistingOIDCProviderArn` parameter if the OIDC provider already exists
- Whether to update an existing CFN stack vs. create a new one

**Exit code 0** = clean account, standard deploy. **Exit code 1** = conflicts found, follow the recommendations.

---

## Standard deploy (new AWS account)

One stack per AWS account. Stack name convention: `hcp-terraform-bootstrap-<account-nickname>`.

```bash
aws cloudformation deploy \
  --stack-name hcp-terraform-bootstrap-<account-nickname> \
  --template-file bootstrap/cfn-terraform-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HCPOrganization=core-aws \
    HCPBootstrapProject=bootstrap-<env> \
    HCPTeamProject=team-<env> \
    KMSAliasName=alias/<account-nickname>-platform
```

Example for the shared dev account:
```bash
aws cloudformation deploy \
  --stack-name hcp-terraform-bootstrap-dev-shared \
  --template-file bootstrap/cfn-terraform-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HCPOrganization=core-aws \
    HCPBootstrapProject=bootstrap-dev \
    HCPTeamProject=team-dev \
    KMSAliasName=alias/dev-shared-platform
```

---

## After deploy — capture outputs

```bash
aws cloudformation describe-stacks \
  --stack-name hcp-terraform-bootstrap-<account-nickname> \
  --query 'Stacks[0].Outputs' --output table
```

Key outputs to record:

| Output | Where to use |
|---|---|
| `PlatformKMSKeyArn` | `bootstrap-accounts-dev/locals.tf` → `kms_key_arn` |
| `TerraformDeployRoleArn` | Auto-derived by the module; verify it matches `arn:aws:iam::<account>:role/TerraformDeployRole` |

---

## Adding a second (or third) client to the same AWS account

**No stack changes needed.** The project-scoped trust policy already covers all workspaces in `bootstrap-dev` and `team-dev`. Simply add the new client entry to `accounts_<client>.tf` or `accounts.tf.json` and apply the control-plane workspace.

---

## Known issue: OIDC provider already exists (409 AlreadyExists)

**Symptom:**
```
AWS::IAM::OIDCProvider CREATE_FAILED
Provider with url https://app.terraform.io already exists (Status Code: 409)
```

**Cause:** AWS allows only one OIDC provider per URL per account. The provider was already created manually or by a previous stack.

**Fix:** Pass the existing provider ARN via `ExistingOIDCProviderArn`. The template skips creation and uses the existing ARN in the role trust policy.

```bash
# 1. Get the existing provider ARN
aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[*].Arn' --output text

# 2. Delete the failed stack if one exists
aws cloudformation delete-stack --stack-name <failed-stack-name>
aws cloudformation wait stack-delete-complete --stack-name <failed-stack-name>

# 3. Redeploy with the existing ARN
aws cloudformation deploy \
  --stack-name hcp-terraform-bootstrap-<account-nickname> \
  --template-file bootstrap/cfn-terraform-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HCPOrganization=core-aws \
    HCPBootstrapProject=bootstrap-<env> \
    HCPTeamProject=team-<env> \
    KMSAliasName=alias/<account-nickname>-platform \
    ExistingOIDCProviderArn=<arn-from-step-1>
```

---

## Known issue: TerraformDeployRole already exists (shared account)

**Symptom:**
```
AWS::IAM::Role CREATE_FAILED
TerraformDeployRole already exists in stack arn:aws:cloudformation:...:stack/hcp-terraform-bootstrap-.../...
```

**Cause:** Another client's stack in this account already created `TerraformDeployRole`. You attempted to create a second stack that also tries to create the same fixed-name role.

**Fix (current template — project-scoped trust):** Do not create a new stack. The existing `TerraformDeployRole` already trusts all workspaces in the project. Just clean up the failed stack — no further action needed.

```bash
# Clean up the failed stack only
aws cloudformation delete-stack --stack-name <failed-stack-name>
aws cloudformation wait stack-delete-complete --stack-name <failed-stack-name>

# Verify the existing role already covers the new client (project-scoped trust)
aws iam get-role --role-name TerraformDeployRole \
  --query 'Role.AssumeRolePolicyDocument.Statement[*].{Sid:Sid,Sub:Condition.StringLike."app.terraform.io:sub"}' \
  --output table
# Expected output:
# AllowBootstrapProject | organization:core-aws:project:bootstrap-dev:workspace:*:run_phase:*
# AllowTeamProject      | organization:core-aws:project:team-dev:workspace:*:run_phase:*
```

---

## Known issue: OIDC provider silently deleted by CFN rollback

**Symptom:**
```
InvalidIdentityToken: No OpenIDConnect provider found in your account for https://app.terraform.io
```
The trust policy references the provider ARN correctly, and `aws iam list-open-id-connect-providers` may have shown it earlier, but `aws iam get-open-id-connect-provider` returns `NoSuchEntity`.

**Cause:** When a CFN stack fails with 409 (OIDC provider already exists) and rolls back, CloudFormation can silently delete the pre-existing OIDC provider as part of cleanup — even though CFN didn't create it. This leaves the account without a provider despite the trust policy referencing one.

**Fix:**
```bash
# 1. Confirm the provider is gone
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::<account-id>:oidc-provider/app.terraform.io

# 2. Clear ExistingOIDCProviderArn on the stack so it recreates the provider
aws cloudformation deploy \
  --stack-name hcp-terraform-bootstrap-<account-nickname> \
  --template-file bootstrap/cfn-terraform-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HCPOrganization=core-aws \
    HCPBootstrapProject=bootstrap-<env> \
    HCPTeamProject=team-<env> \
    KMSAliasName=alias/<account-nickname>-platform \
    ExistingOIDCProviderArn=""

# 3. Verify
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::<account-id>:oidc-provider/app.terraform.io
# Must show: ClientIDList: [aws.workload.identity]
```

> **Important:** You must explicitly pass `ExistingOIDCProviderArn=""` (empty string). If you omit the parameter, `aws cloudformation deploy` uses the previous stored value and makes no changes.

---

## Real example: Mindrithm + test-client sharing account 889851937279 (2026-04-26)

Both `mindrithm-dev` and `test-client-dev` use AWS account `889851937279`. When deploying the bootstrap stack for Mindrithm, two errors occurred in sequence:

**Error 1 — OIDC provider already existed:**
```
AWS::IAM::OIDCProvider CREATE_FAILED: Provider with url https://app.terraform.io already exists (409)
```
Fix: added `ExistingOIDCProviderArn=arn:aws:iam::889851937279:oidc-provider/app.terraform.io`

**Error 2 — TerraformDeployRole owned by test-client stack:**
```
AWS::IAM::Role CREATE_FAILED: TerraformDeployRole already exists in stack hcp-terraform-bootstrap-test-client-dev
```
Fix: the per-client `ClientId`/`AdditionalClientId` design was replaced with project-scoped trust. The existing `hcp-terraform-bootstrap-test-client-dev` stack was updated with the new template — both clients are now covered by the project-level wildcard.

Active stack: `hcp-terraform-bootstrap-test-client-dev`
KMS key ARN: `arn:aws:kms:us-east-1:889851937279:key/2890479f-ca9b-4150-a025-5e821899e29c`
Recorded in: `bootstrap-accounts-dev/locals.tf`

---

## Decision tree

```
Deploying cfn-terraform-bootstrap for an AWS account?
│
├─ Has this account ever had the stack before?
│   └─ NO  → Standard deploy (no extra parameters)
│   └─ YES → Update the existing stack with latest template
│
├─ Does app.terraform.io OIDC provider already exist?
│   └─ YES → Add ExistingOIDCProviderArn parameter
│
└─ Does TerraformDeployRole already exist (another stack owns it)?
    └─ YES → Delete the failed new stack. The existing role already covers
             all clients via project-scoped trust. No further action needed.
```

---

## Relevant files

| File | Purpose |
|---|---|
| `bootstrap/cfn-terraform-bootstrap.yaml` | The CloudFormation template |
| `bootstrap-accounts-dev/locals.tf` | `kms_key_arn` for the shared dev account |
| `bootstrap-accounts-dev/accounts.tf.json` | `kms_key_arn` per static account entry |
