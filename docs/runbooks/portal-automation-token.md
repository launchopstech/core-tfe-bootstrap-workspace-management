# Runbook: Portal Automation Token (TFE_TOKEN)

Every account-portal workspace (e.g. `mindrithm-dev`, `test-client-dev`) uses the HCP Terraform provider to create child deployer workspaces (vpc, rds, api, etc.). To do this it needs a valid HCP Terraform API token — `TFE_TOKEN` — set as a sensitive environment variable. Without it the workspace runner's default token is used, which lacks permission to create workspaces in other projects.

---

## How it works (automated)

The `bootstrap-accounts-varset` root (`00-bootstrap-account-workspace-management` workspace) creates a `portal-automation-token` variable set and attaches it to all five `team-*` projects:

```
00-bootstrap-account-workspace-management apply
  → tfe_variable_set.portal_automation (portal-automation-token)
      → TFE_TOKEN = <token> (sensitive env)
  → tfe_project_variable_set.portal_automation (attached to)
      → team-dev
      → team-qa
      → team-prod
      → team-workbench
      → team-sbx
          → every portal workspace in these projects inherits TFE_TOKEN ✓
```

**No per-client manual steps required once the variable set is active.**

---

## One-time setup

### Step 1 — Get a token

**Option A (recommended when plans allow): `platform-automation` team token**
1. HCP Terraform → Settings → Teams → Create team: `platform-automation`
2. Add Admin access to all `team-*` projects
3. Settings → Teams → `platform-automation` → Team API Token → Generate

**Option B (single-operator / free plan): owners team token**
1. HCP Terraform → Settings → Teams → `owners` → Team API Token → Generate
2. Acceptable for single-operator setups; rotate periodically

### Step 2 — Set `portal_automation_token` on the varset workspace

Set it as a sensitive workspace variable on `00-bootstrap-account-workspace-management`:

```bash
TFE_API=$(cat ~/.terraform.d/credentials.tfrc.json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d['credentials']['app.terraform.io']['token'])")

curl -s -X POST \
  -H "Authorization: Bearer $TFE_API" \
  -H "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/workspaces/ws-WHUEb5yo5oGcgKw7/vars" \
  -d '{
    "data": {
      "type": "vars",
      "attributes": {
        "key": "portal_automation_token",
        "value": "<YOUR_TOKEN>",
        "category": "terraform",
        "sensitive": true,
        "description": "Team token injected as TFE_TOKEN into team-* project portal workspaces."
      }
    }
  }'
```

> Workspace ID `ws-WHUEb5yo5oGcgKw7` = `00-bootstrap-account-workspace-management`.

### Step 3 — Trigger a run

In HCP Terraform, trigger a new run on `00-bootstrap-account-workspace-management`. This creates the `portal-automation-token` variable set and attaches it to all `team-*` projects.

---

## Token rotation

To rotate the token:

1. Generate a new token (same team or owners)
2. Update the workspace variable `portal_automation_token` on `00-bootstrap-account-workspace-management` (UI or API)
3. Trigger a new run — the variable set updates automatically
4. All portal workspaces pick up the new token on their next run

---

## Known issue: manual fix required for existing workspaces

If a portal workspace was created **before** the variable set was attached to the project, it will **not** automatically pick up the variable set. You must either:

- Delete and recreate the workspace (it will inherit the set on creation), or
- Manually set `TFE_TOKEN` via API:

```bash
TFE_API=$(cat ~/.terraform.d/credentials.tfrc.json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d['credentials']['app.terraform.io']['token'])")

curl -s -X POST \
  -H "Authorization: Bearer $TFE_API" \
  -H "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/workspaces/<WS_ID>/vars" \
  -d '{
    "data": {
      "type": "vars",
      "attributes": {
        "key": "TFE_TOKEN",
        "value": "<YOUR_TOKEN>",
        "category": "env",
        "sensitive": true
      }
    }
  }'
```

> This was the manual fix applied to `mindrithm-dev` (ws-GhUjBw1Qnwb556EN) on 2026-04-26 before the automation was in place.

---

## Relevant files

| File | Purpose |
|------|---------|
| `bootstrap-accounts-varset/varset.tf` | Defines `tfe_variable_set.portal_automation`, `tfe_variable.portal_tfe_token`, and `tfe_project_variable_set.portal_automation` |
| `bootstrap-accounts-varset/variables.tf` | `portal_automation_token` input variable |
| `bootstrap-accounts-varset/outputs.tf` | `portal_automation_variable_set_id` output |
| `docs/token-strategy.md` | Full token strategy across all layers |
