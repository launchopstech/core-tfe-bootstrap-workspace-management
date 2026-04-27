# Runbook: Tearing Down a Client Environment

Use this runbook when fully removing a client from an AWS account — destroying all Terraform-managed infrastructure and deleting HCP Terraform workspaces.

---

## Why Terraform destroy alone is not enough

`TerraformDeployPolicy` (created by `cfn-terraform-bootstrap.yaml`) contains an explicit **DenyAuditTamper** statement that blocks `TerraformDeployRole` from deleting audit infrastructure — even during a `terraform destroy`. This is intentional: it prevents a compromised Terraform run from silently wiping evidence of its own activity.

Blocked actions:

| Action | Sid |
|---|---|
| `cloudtrail:DeleteTrail` | `DenyAuditTamper` |
| `cloudtrail:StopLogging` | `DenyAuditTamper` |
| `cloudtrail:UpdateTrail` | `DenyAuditTamper` |
| `config:DeleteConfigurationRecorder` | `DenyAuditTamper` |
| `config:StopConfigurationRecorder` | `DenyAuditTamper` |
| `config:DeleteDeliveryChannel` | `DenyAuditTamper` |
| `guardduty:DeleteDetector` | `DenyAuditTamper` |
| `securityhub:DisableSecurityHub` | `DenyAuditTamper` |

Additionally, the S3 logging bucket is created with `force_destroy = false` — Terraform cannot delete it while objects exist.

**These resources must be deleted manually with admin credentials before running Terraform destroy.**

---

## Workspace naming convention

Workspace names depend on whether `workspace_env_suffix_mode` is set for the client:

| Mode | Pattern | Example (vpc) |
|---|---|---|
| `workspace_env_suffix_mode = true` | `<client>-<service>-<env>` | `mindrithm-vpc-dev` |
| `workspace_env_suffix_mode = false` (default) | `<client>-<env>-<service>` | `acme-dev-vpc` |

Check `bootstrap-accounts-dev/accounts_<client>.tf` to confirm which mode is set before looking up workspaces.

---

## Shared account warning

Config recorder and GuardDuty detector are **account-level singletons**. In a shared account, secondary clients are configured with `enable_config = false` and `enable_guardduty = false` — meaning they rely on the primary client's resources for account-wide security monitoring.

**Before tearing down the primary client in a shared account:**
1. Identify which secondary clients have `enable_config = false` or `enable_guardduty = false`
2. Set `enable_config = true` / `enable_guardduty = true` on a remaining client's secure-baseline
3. Apply that workspace so it takes ownership of the singletons
4. Only then run pre-teardown for the departing client

The `pre-teardown.sh` script detects other client trails in the account and **refuses** to delete Config/GuardDuty singletons if other clients are present, printing a clear error.

---

## Step 1 — Lock all client workspaces first

Before running pre-teardown, lock every client workspace in HCP Terraform to prevent queued or auto-triggered runs from recreating resources between cleanup and destroy.

```bash
TFE_TOKEN=<your-token>

lock_ws() {
  local ws_id=$1 ws_name=$2
  curl -s -X POST \
    -H "Authorization: Bearer $TFE_TOKEN" \
    -H "Content-Type: application/vnd.api+json" \
    "https://app.terraform.io/api/v2/workspaces/$ws_id/actions/lock" \
    -d '{"reason":"Pre-teardown lock — manual cleanup in progress"}' \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('Locked:', d['data']['attributes']['locked'], '$ws_name')"
}

lock_ws <ws-id-secure-baseline> "mindrithm-secure-baseline-dev"
lock_ws <ws-id-portal>          "mindrithm-dev"
# ... all other workspaces
```

> **Why:** If a workspace runs an apply between the manual resource deletion and the Terraform destroy, it will detect drift and recreate the deleted resource. The destroy will then fail with `AccessDeniedException` on resources TerraformDeployRole cannot delete.

---

## Step 2 — Run pre-teardown script

Authenticate with admin credentials (not TerraformDeployRole), then:

```bash
./bootstrap/pre-teardown.sh \
  --client-id <client-id> \
  --env <env>
```

The script handles:
- Deletes the CloudTrail trail (`<client>-<env>-trail`)
- Empties and deletes the S3 logging bucket (`<client>-<env>-logs-<account-id>`)
- Deletes Config recorder and delivery channel (skipped with error if other clients exist)
- Deletes GuardDuty detector tagged for this client (skipped with error if other clients exist)

Exit code 0 = safe to proceed. Exit code 1 = fix errors before continuing.

---

## Step 2 — Enable destroy plans on affected workspaces

There are three workspace classes with different `allow_destroy_plan` settings (see `bootstrap-accounts/workspaces.tf`):

| Workspace | HCP Terraform name | `allow_destroy_plan` | Action needed |
|---|---|---|---|
| Bootstrap/preflight | `bootstrap-<client>-<env>` | `true` | None — already enabled |
| **Account portal** | `<client>-<env>` (e.g. `mindrithm-dev`) | `false` | **Must enable** |
| **Service workspaces** | `<client>-<service>-<env>` or `<client>-<env>-<service>` | `false` | **Must enable** |

Enable destroy plans via the TFE API for the portal and all service workspaces:

```bash
TFE_TOKEN=<your-token>

enable_destroy() {
  local ws_id=$1 ws_name=$2
  curl -s -X PATCH \
    -H "Authorization: Bearer $TFE_TOKEN" \
    -H "Content-Type: application/vnd.api+json" \
    "https://app.terraform.io/api/v2/workspaces/$ws_id" \
    -d '{"data":{"type":"workspaces","attributes":{"allow-destroy-plan":true}}}' \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('allow-destroy-plan:', d['data']['attributes']['allow-destroy-plan'], '$ws_name')"
}

# Look up workspace IDs:
curl -s -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/core-aws/workspaces?search%5Bname%5D=<client>&page%5Bsize%5D=20" \
  | python3 -c "import sys,json; [print(w['id'], w['attributes']['name']) for w in json.load(sys.stdin)['data']]"

# Enable on portal + all service workspaces (NOT bootstrap-<client>-<env> — already true)
enable_destroy <ws-id-portal>          "<client>-<env>"
enable_destroy <ws-id-api>             "<client>-api-<env>"
enable_destroy <ws-id-rds>             "<client>-rds-<env>"
enable_destroy <ws-id-secrets>         "<client>-secrets-<env>"
enable_destroy <ws-id-vpc>             "<client>-vpc-<env>"
enable_destroy <ws-id-secure-baseline> "<client>-secure-baseline-<env>"
```

---

## Step 3 — Destroy workspaces in order

Trigger **destroy runs** in HCP Terraform (Settings → Destruction and Deletion → Queue destroy plan). Run in this order — wait for each step to complete before the next:

```
Step 1 (parallel):
  <client>-api-<env>    OR  <client>-<env>-api    (see naming convention above)
  <client>-rds-<env>    OR  <client>-<env>-rds

Step 2 (after both above complete):
  <client>-secrets-<env>    OR  <client>-<env>-secrets
  <client>-vpc-<env>        OR  <client>-<env>-vpc

Step 3:
  <client>-secure-baseline-<env>    OR  <client>-<env>-secure-baseline

Step 4:
  <client>-<env>  (account portal workspace — e.g. mindrithm-dev)

Step 5 (last — already has allow_destroy_plan=true, no Step 2 needed):
  bootstrap-<client>-<env>  (bootstrap/preflight workspace — e.g. bootstrap-mindrithm-dev)
```

> **Note:** If a destroy run fails with `AccessDeniedException` on any audit resource, the pre-teardown script missed it. Delete the resource manually and re-run the destroy.

---

## Step 4 — Delete workspaces from HCP Terraform

After all destroy runs complete (0 resources), delete the workspaces via the UI or API:

```bash
delete_ws() {
  local ws_id=$1
  curl -s -X DELETE \
    -H "Authorization: Bearer $TFE_TOKEN" \
    "https://app.terraform.io/api/v2/workspaces/$ws_id"
  echo "Deleted $ws_id"
}
```

Workspaces to delete (in any order once all destroy runs show 0 resources):

| Workspace | Class | Notes |
|---|---|---|
| `bootstrap-<client>-<env>` | Bootstrap/preflight | e.g. `bootstrap-mindrithm-dev` |
| `<client>-<env>` | Account portal | e.g. `mindrithm-dev` — the factory/controller, NOT a service workspace |
| `<client>-secure-baseline-<env>` or `<client>-<env>-secure-baseline` | Service | |
| `<client>-secrets-<env>` or `<client>-<env>-secrets` | Service | |
| `<client>-vpc-<env>` or `<client>-<env>-vpc` | Service | |
| `<client>-rds-<env>` or `<client>-<env>-rds` | Service | |
| `<client>-api-<env>` or `<client>-<env>-api` | Service | |

---

## Step 5 — Remove client from control plane

Remove `bootstrap-accounts-<env>/accounts_<client>.tf` and apply `bootstrap-account-workspace-management-<env>`. This removes the client from Terraform state so no ghost resources remain.

---

## Step 6 — Shared account check

If other clients share the same AWS account, verify their workspaces are still healthy:

```bash
# OIDC provider still exists
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::<account-id>:oidc-provider/app.terraform.io

# TerraformDeployRole still exists
aws iam get-role --role-name TerraformDeployRole
```

Trigger a plan (not apply) on the remaining client's secure-baseline workspace to verify no drift.

---

## TODO: GitHub Actions automation

The pre-teardown step and workspace destroy orchestration should eventually be automated as a GitHub Actions workflow triggered on a `client-offboard` label or manual dispatch event:

1. Authenticate to the target AWS account via OIDC
2. Run `bootstrap/pre-teardown.sh --client-id $CLIENT_ID --env $ENV`
3. Enable destroy plans on all workspaces via TFE API
4. Trigger HCP Terraform destroy runs via TFE API in dependency order (poll for completion between steps)
5. Delete workspaces via TFE API
6. Open a PR removing `accounts_<client>.tf`

Tracking: open a GitHub issue labelled `automation` / `offboarding` when ready to build.

---

## Quick reference

| Symptom | Cause | Fix |
|---|---|---|
| `AccessDeniedException: cloudtrail:DeleteTrail` | DenyAuditTamper policy | Run `pre-teardown.sh` first |
| `BucketNotEmpty` on S3 delete | `force_destroy = false` | Run `pre-teardown.sh` first |
| `AccessDeniedException: config:DeleteConfigurationRecorder` | DenyAuditTamper policy | Run `pre-teardown.sh` first |
| `AccessDeniedException: guardduty:DeleteDetector` | DenyAuditTamper policy | Run `pre-teardown.sh` first |
| Destroy plan blocked in HCP Terraform UI | `allow_destroy_plan = false` on portal/service workspaces | Enable via TFE API (Step 2) — bootstrap workspace is already `true` |
| Config/GuardDuty skipped with error | Shared account — other clients depend on singletons | Transfer singleton ownership first (see Shared Account Warning) |

---

## Relevant files

| File | Purpose |
|---|---|
| `bootstrap/pre-teardown.sh` | Pre-teardown cleanup script (requires admin credentials) |
| `bootstrap/cfn-terraform-bootstrap.yaml` | CFN template containing DenyAuditTamper policy |
| `bootstrap-accounts/workspaces.tf` | `allow_destroy_plan = false` on service workspaces (line 160) |
| `bootstrap-accounts-dev/accounts_<client>.tf` | Client entry to remove after teardown |
| `docs/runbooks/shared-account-onboarding.md` | Singleton ownership transfer guidance |
