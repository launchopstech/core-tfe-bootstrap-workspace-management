# Runbook: GitHub Org Migration

Use this runbook whenever the GitHub repository is transferred to a new organization or a new VCS OAuth connection is needed in HCP Terraform.

---

## Prerequisites

- HCP Terraform user token with org admin permissions (`terraform login` already completed)
- Owner access to the GitHub organization the repo is moving to
- The new GitHub org name and repo name confirmed

---

## Known Issues (Discovered 2026-04-26)

### Issue 1 — `backend_override.tf` breaks `hcp-bootstrap` init

`scripts/local-backend-setup.sh` writes a `cloud {}` backend override to **all** Terraform roots including `hcp-bootstrap/`. However, `hcp-bootstrap` is designed to run locally against local state (not HCP Terraform remote execution). The generated file lacks the required `workspaces { name }` block and causes `terraform init` to fail with:

```
Error: Invalid workspaces configuration — Missing workspace mapping strategy
```

**Fix before every local `hcp-bootstrap` run:**
```bash
rm -f hcp-bootstrap/backend_override.tf
```

**Root cause:** `hcp-bootstrap` should be excluded from `scripts/local-backend-setup.sh`. Edit the `ROOTS` array in that script and remove `"hcp-bootstrap"`.

---

### Issue 2 — GitHub OAuth App pending transfer silently blocks org access

If the GitHub OAuth App (the one registered in HCP Terraform Settings → VCS Providers) is in a **pending transfer** state to another org, re-authorizing the VCS provider on HCP Terraform will **not** prompt GitHub to grant access to the destination org. The transfer limbo state causes GitHub to silently skip the org grant step.

**Symptom:** HCP Terraform returns `Repository doesn't exist or isn't accessible` even after re-authorization.

**Fix:**
1. Go to GitHub → **Developer Settings** → **OAuth Apps** → find the HCP Terraform app
2. If you see "This application is pending transfer to `<org>`" — click **Cancel transfer**
3. Proceed with the VCS provider steps below

---

### Issue 3 — VCS provider re-creation generates a new OAuth token ID

Every time a VCS provider is **deleted and re-added** in HCP Terraform, a new `ot-...` OAuth token ID is issued. This ID must be updated in **two separate places** — Terraform code and HCP Terraform workspace variables (set out-of-band, not managed by Terraform).

---

### Issue 4 — `vcs_repo_identifier` must be updated in multiple files

The old org name is hardcoded in several places across the repo. All must be updated atomically before re-running the bootstrap sequence.

---

## Migration Steps

### Step 1 — Cancel any pending GitHub OAuth App transfer

See Issue 2 above. Go to GitHub → Developer Settings → OAuth Apps and cancel any pending transfer before proceeding.

---

### Step 2 — Re-add the VCS provider in HCP Terraform

1. Go to `app.terraform.io` → **Settings** → **Version Control** → **Providers**
2. Delete the existing GitHub provider
3. Click **Add VCS Provider** → **GitHub**
4. HCP Terraform shows a **callback URL** and prompts for Client ID / Secret
5. **Before clicking authorize:** go to GitHub → **Developer Settings** → **OAuth Apps** → update the app's **Authorization callback URL** to match exactly what HCP Terraform shows
6. Enter the GitHub OAuth App's Client ID and Client Secret into HCP Terraform
7. Click **Connect and continue** → GitHub prompts for authorization
8. On the GitHub authorization screen, click **Grant** next to the new org name
9. Complete authorization
10. **Copy the new `ot-...` token ID** shown in HCP Terraform

If GitHub does not show the org grant prompt, go to:
**GitHub → Settings → Connections → Applications → find the app → Grant** next to the org.

---

### Step 3 — Remove `backend_override.tf` from `hcp-bootstrap`

```bash
rm -f hcp-bootstrap/backend_override.tf
```

---

### Step 4 — Update `hcp-bootstrap/terraform.tfvars`

```hcl
vcs_repo_identifier = "<new-org>/<repo-name>"
vcs_oauth_token_id  = "<new-ot-...>"
vcs_branch          = "develop"
```

File: `hcp-bootstrap/terraform.tfvars`

---

### Step 5 — Run `hcp-bootstrap` locally

```bash
cd hcp-bootstrap
terraform init
terraform plan   # verify: 3 workspaces updating vcs_repo block
terraform apply -auto-approve
```

Expected: 3 control-plane workspaces updated (`0 added, 3 changed, 0 destroyed`).

---

### Step 6 — Update `aws_core_oauth_token_id` workspace variables via API

The control-plane workspaces (`bootstrap-account-workspace-management-dev` and `bootstrap-account-workspace-management-workbench`) have an `aws_core_oauth_token_id` workspace variable that holds the VCS OAuth token ID. This variable is **not managed by Terraform** and must be updated manually.

```bash
TFE_TOKEN=$(cat ~/.terraform.d/credentials.tfrc.json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d['credentials']['app.terraform.io']['token'])")

NEW_TOKEN="ot-REPLACE_WITH_NEW_TOKEN"

# Find the variable IDs
for ws_id in ws-FuzdTZCd7NCxnkni ws-rfKXrj5seHeci66F; do
  echo "=== Workspace $ws_id ==="
  VAR_ID=$(curl -s -H "Authorization: Bearer $TFE_TOKEN" \
    "https://app.terraform.io/api/v2/workspaces/$ws_id/vars" | \
    python3 -c "
import json,sys
d=json.load(sys.stdin)
for v in d.get('data',[]):
    if v['attributes'].get('key') == 'aws_core_oauth_token_id':
        print(v['id'])
")
  echo "Updating $VAR_ID"
  curl -s -X PATCH \
    -H "Authorization: Bearer $TFE_TOKEN" \
    -H "Content-Type: application/vnd.api+json" \
    "https://app.terraform.io/api/v2/workspaces/$ws_id/vars/$VAR_ID" \
    -d "{\"data\":{\"type\":\"vars\",\"id\":\"$VAR_ID\",\"attributes\":{\"value\":\"$NEW_TOKEN\",\"sensitive\":true}}}" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print('OK' if not d.get('errors') else d['errors'])"
done
```

> **Note:** Workspace IDs shown are for the `core-aws` org at the time of writing. Verify against actual workspace IDs if they have changed.

---

### Step 7 — Update `vcs_repo_identifier` in all accounts files

Replace `<old-org>` with `<new-org>` in every file that references the repo identifier:

| File | Field |
|------|-------|
| `hcp-bootstrap/terraform.tfvars` | `vcs_repo_identifier` (done in Step 4) |
| `bootstrap-accounts-dev/accounts.tf.json` | `"vcs_repo_identifier"` per account entry |
| `bootstrap-accounts-workbench/accounts.tf.json` | `"vcs_repo_identifier"` per account entry |
| `bootstrap-accounts-dev/accounts_mindrithm.tf` | `vcs_repo_identifier` |
| Any other `accounts_*.tf` files | `vcs_repo_identifier` / `service_vcs_repo_identifier` |

Quick find:
```bash
grep -r "bomatronix" . --include="*.tf" --include="*.json" --include="*.tfvars" -l
```

---

### Step 8 — Trigger downstream HCP Terraform runs

1. In HCP Terraform, navigate to `bootstrap-account-workspace-management-dev`
2. Click **Actions** → **Start new run** → **Plan and apply**
3. Repeat for `bootstrap-account-workspace-management-workbench`
4. Monitor runs — workspace VCS repos should update to the new org/branch

---

## Verification

- [ ] `hcp-bootstrap` apply completes: `0 added, 3 changed, 0 destroyed`
- [ ] HCP Terraform UI shows all 3 control-plane workspaces with new VCS identifier and `develop` branch
- [ ] `bootstrap-account-workspace-management-dev` run succeeds (no `OAuth token does not exist` errors)
- [ ] `bootstrap-account-workspace-management-workbench` run succeeds
- [ ] Runtime workspace VCS repos point to `<new-org>/...`
