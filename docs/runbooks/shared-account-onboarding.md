# Runbook: Adding a New Client to a Shared AWS Account

Use this runbook when two or more clients will share the same AWS account ID. This is common during early-stage multi-tenant setups where each client does not yet have a dedicated account.

---

## The problem with shared accounts

Several AWS and Terraform resources are **account-level singletons** — only one can exist per account per region. When the first client's workspaces already created these, any subsequent client's `secure-baseline` workspace will fail trying to create duplicates.

Additionally, the IAM OIDC provider and `TerraformDeployRole` created by `bootstrap/cfn-terraform-bootstrap.yaml` are also singletons. Attempting to create a second CFN stack in the same account for the second client will fail.

**All of these issues are recoverable — but they must be anticipated before running Terraform.**

---

## Step 0 — Run the pre-flight check

Always run this first, authenticated to the target AWS account:

```bash
./bootstrap/pre-flight-check.sh \
  --client-id <new-client-id> \
  --env <env>
```

The script checks all conflict sources and prints exactly which `enable_*` flags to set and which CFN parameters to pass. Exit code 0 = clean account, 1 = conflicts found.

---

## Singleton resource reference

### CFN bootstrap singletons (`cfn-terraform-bootstrap.yaml`)

| Resource | Conflict | Fix |
|---|---|---|
| `AWS::IAM::OIDCProvider` for `app.terraform.io` | Only 1 per account | Pass `ExistingOIDCProviderArn=<arn>` to CFN deploy |
| `AWS::IAM::Role` `TerraformDeployRole` | Only 1 per account | Update the EXISTING stack — do not create a new one |

### Secure-baseline module singletons (`enable_*` flags)

| Resource | Flag | Default | Singleton scope |
|---|---|---|---|
| `aws_accessanalyzer_analyzer` (ACCOUNT type) | `enable_access_analyzer` | `true` | 1 per account per region |
| `aws_guardduty_detector` | `enable_guardduty` | `true` | 1 per account per region |
| `aws_securityhub_account` | `enable_security_hub` | `true` | 1 per account |
| `aws_config_configuration_recorder` | `enable_config` | `true` | 1 active per account per region |

**Not a singleton:**
- `aws_cloudtrail` — up to 5 trails per region; each client gets their own with their own S3 bucket ✓
- `aws_sns_topic` — names are client-prefixed, no conflict ✓
- `aws_s3_bucket` (logs) — names are client-prefixed, no conflict ✓

---

## Complete workflow for a shared account

### 1. Run pre-flight check

```bash
./bootstrap/pre-flight-check.sh --client-id <new-client> --env dev
```

Review output carefully. Note:
- Any existing OIDC provider ARN
- Whether `TerraformDeployRole` already exists
- Which `enable_*` flags need to be `false`

### 2. Handle the CFN stack

**If `TerraformDeployRole` already exists** (pre-flight check found it):

Do NOT create a new CFN stack. Update the existing one — the project-scoped trust policy already covers all clients:

```bash
aws cloudformation deploy \
  --stack-name hcp-terraform-bootstrap-<existing-stack> \
  --template-file bootstrap/cfn-terraform-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HCPOrganization=core-aws \
    HCPBootstrapProject=bootstrap-<env> \
    HCPTeamProject=team-<env> \
    KMSAliasName=alias/<existing-alias> \
    ExistingOIDCProviderArn=<arn-from-preflight>
```

The update will be a no-op if nothing changed (which is fine — it confirms the stack is current).

**If neither OIDC provider nor role exists** (clean account):

```bash
aws cloudformation deploy \
  --stack-name hcp-terraform-bootstrap-<nickname> \
  --template-file bootstrap/cfn-terraform-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    HCPOrganization=core-aws \
    HCPBootstrapProject=bootstrap-<env> \
    HCPTeamProject=team-<env> \
    KMSAliasName=alias/<nickname>-platform
```

### 3. Capture KMS key ARN

```bash
aws cloudformation describe-stacks \
  --stack-name hcp-terraform-bootstrap-<stack> \
  --query 'Stacks[0].Outputs[?OutputKey==`PlatformKMSKeyArn`].OutputValue' \
  --output text
```

Set this as `kms_key_arn` in `bootstrap-accounts-dev/locals.tf` (if all clients in the file share the same account) or in the per-client `accounts_<client>.tf`.

### 4. Create the client account entry

Create `bootstrap-accounts-dev/accounts_<client>.tf`. For a shared account, set all singleton `enable_*` flags that the pre-flight check flagged:

```hcl
locals {
  accounts_<client> = {
    "<client>-dev" = {
      account_id   = "<shared-account-id>"
      client_id    = "<client>"
      env          = "dev"
      # ... other fields ...
      service_workspace_variables = {
        "secure-baseline" = {
          kms_key_arn            = local.kms_key_arn
          enable_config          = false  # if already exists in account
          enable_guardduty       = false  # if already exists in account
          enable_security_hub    = false  # if already exists in account
          enable_access_analyzer = false  # if already exists in account
        }
        # ... other services ...
      }
    }
  }
}
```

### 5. Apply control plane and run workspaces

```bash
# Apply bootstrap-account-workspace-management-dev (creates the workspaces + variables)
# Then trigger in dependency order:
# 1. <client>-secure-baseline-<env>  and  <client>-secrets-<env>  (parallel)
# 2. <client>-vpc-<env>
# 3. <client>-rds-<env>  and  <client>-api-<env>  (parallel)
```

---

## Known issues encountered (2026-04-26, account 889851937279)

When adding `mindrithm-dev` to an account already containing `test-client-dev`, the following failures occurred in sequence:

### Issue 1 — OIDC provider 409 AlreadyExists
`AWS::IAM::OIDCProvider CREATE_FAILED: Provider with url https://app.terraform.io already exists`

Fix: passed `ExistingOIDCProviderArn=arn:aws:iam::889851937279:oidc-provider/app.terraform.io`

### Issue 2 — TerraformDeployRole already exists in another stack
`AWS::IAM::Role CREATE_FAILED: TerraformDeployRole already exists in stack hcp-terraform-bootstrap-test-client-dev`

Fix: updated the existing stack instead of creating a new one. Trust policy is project-scoped so both clients are covered automatically.

### Issue 3 — OIDC provider silently deleted by CFN rollback
After Issue 1's failed stack rolled back, the pre-existing OIDC provider was deleted. Service workspaces started failing with:
`InvalidIdentityToken: No OpenIDConnect provider found in your account for https://app.terraform.io`

Fix: redeployed existing stack with `ExistingOIDCProviderArn=""` (empty) to force recreation.

> **Lesson:** After ANY failed CFN stack rollback in an account, verify the OIDC provider still exists with `aws iam get-open-id-connect-provider`. If missing, clear `ExistingOIDCProviderArn` and redeploy.

### Issue 4 — Access Analyzer quota exceeded
`ServiceQuotaExceededException: Analyzer limit exceeded`

Fix: added `enable_access_analyzer = false` to Mindrithm's secure-baseline config.

### Issue 5 — CloudTrail bucket policy race condition (module bug)
`InsufficientS3BucketPolicyException: Incorrect S3 bucket policy detected for bucket: mindrithm-dev-logs-889851937279`

Root cause: `aws_cloudtrail.main` had no `depends_on` for `aws_s3_bucket_policy.logs`. Terraform applied both in parallel — CloudTrail validated the bucket policy before it was written.

Fix: added `depends_on = [aws_s3_bucket_policy.logs]` to `aws_cloudtrail.main` in `modules/aws/secure-baseline/main.tf`. This is a module-level fix that benefits all clients going forward.

---

## Quick reference — pre-flight check output vs. fix

| Pre-flight warning | Required fix |
|---|---|
| OIDC provider exists | Add `ExistingOIDCProviderArn=<arn>` to CFN deploy |
| TerraformDeployRole exists | Update existing CFN stack, do not create new one |
| Access Analyzer exists | `enable_access_analyzer = false` |
| GuardDuty detector exists | `enable_guardduty = false` |
| Security Hub enabled | `enable_security_hub = false` |
| Config recorder exists | `enable_config = false` |
| CloudTrail trail exists | No action — multiple trails are fine |

---

## Relevant files

| File | Purpose |
|---|---|
| `bootstrap/pre-flight-check.sh` | Automated conflict detection before onboarding |
| `bootstrap/cfn-terraform-bootstrap.yaml` | CFN template (OIDC + TerraformDeployRole + KMS) |
| `docs/runbooks/cfn-oidc-bootstrap.md` | CFN deploy detail + known issues |
| `modules/aws/secure-baseline/main.tf` | Secure-baseline resources (singletons + CloudTrail fix) |
| `modules/aws/secure-baseline/variables.tf` | All `enable_*` flags with singleton documentation |
| `bootstrap-accounts-dev/accounts_mindrithm.tf` | Reference example of a shared-account client entry |
