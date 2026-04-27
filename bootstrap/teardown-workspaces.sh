#!/usr/bin/env bash
# =============================================================================
# teardown-workspaces.sh — Destroy and delete all HCP Terraform workspaces
#                          for a client after pre-teardown.sh has been run.
#
# Usage:
#   ./bootstrap/teardown-workspaces.sh \
#     --client-id <id> \
#     --env <env> \
#     [--org <hcp-org>] \
#     [--dry-run]
#
# What it does:
#   1. Locks all client workspaces (prevents drift-repair applies during cleanup)
#   2. Enables allow_destroy_plan on portal + service workspaces
#   3. Triggers destroy runs in dependency order, polling until complete
#   4. Deletes all workspaces once resource counts reach 0
#
# Prerequisites:
#   - TFE_TOKEN env var set (HCP Terraform team/org token)
#   - pre-teardown.sh already run successfully (AWS-side cleanup done)
#
# Dependency order (hard-coded):
#   Step 1 (parallel): api, rds
#   Step 2 (parallel): secrets, vpc
#   Step 3:            secure-baseline
#   Step 4:            <client>-<env>   (portal workspace)
#   Step 5:            bootstrap-<client>-<env>  (already allow_destroy_plan=true)
#
# Exit codes:
#   0 = all workspaces destroyed and deleted
#   1 = one or more steps failed
#   2 = usage error or missing dependencies
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
info() { echo -e "  ${BOLD}→${NC} $*"; }

# ── Parse args ───────────────────────────────────────────────────────────────
CLIENT_ID=""
ENV="dev"
ORG="core-aws"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --env)       ENV="$2";       shift 2 ;;
    --org)       ORG="$2";       shift 2 ;;
    --dry-run)   DRY_RUN=true;   shift ;;
    --help|-h)
      sed -n '/^# Usage/,/^# Exit/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

if [[ -z "$CLIENT_ID" ]]; then
  echo "Error: --client-id is required" >&2; exit 2
fi
if [[ -z "${TFE_TOKEN:-}" ]]; then
  echo "Error: TFE_TOKEN env var is required" >&2; exit 2
fi

TFE_API="https://app.terraform.io/api/v2"
ERRORS=0

echo ""
echo -e "${BOLD}=== Workspace Teardown: ${CLIENT_ID}-${ENV} ===${NC}"
echo -e "  Org     : ${BOLD}${ORG}${NC}"
echo -e "  Dry run : ${BOLD}${DRY_RUN}${NC}"
echo ""

# ── Helper: TFE API call ─────────────────────────────────────────────────────
tfe() {
  local method=$1 path=$2 data=${3:-}
  if [[ -n "$data" ]]; then
    curl -s -X "$method" \
      -H "Authorization: Bearer $TFE_TOKEN" \
      -H "Content-Type: application/vnd.api+json" \
      "$TFE_API$path" -d "$data"
  else
    curl -s -X "$method" \
      -H "Authorization: Bearer $TFE_TOKEN" \
      "$TFE_API$path"
  fi
}

# ── Helper: find workspace ID by name ────────────────────────────────────────
ws_id() {
  local name=$1
  tfe GET "/organizations/$ORG/workspaces/$name" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('id',''))" 2>/dev/null || true
}

# ── Helper: get resource count ───────────────────────────────────────────────
ws_resource_count() {
  local ws_id=$1
  tfe GET "/workspaces/$ws_id" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('attributes',{}).get('resource-count',0))" 2>/dev/null || echo "0"
}

# ── Helper: lock workspace ───────────────────────────────────────────────────
lock_workspace() {
  local ws_id=$1 name=$2
  [[ "$DRY_RUN" == "true" ]] && { info "[dry-run] Would lock $name"; return; }
  tfe POST "/workspaces/$ws_id/actions/lock" \
    '{"reason":"Teardown in progress — locked by teardown-workspaces.sh"}' > /dev/null
  ok "Locked $name"
}

# ── Helper: enable destroy plan ───────────────────────────────────────────────
enable_destroy() {
  local ws_id=$1 name=$2
  [[ "$DRY_RUN" == "true" ]] && { info "[dry-run] Would enable destroy plan on $name"; return; }
  tfe PATCH "/workspaces/$ws_id" \
    '{"data":{"type":"workspaces","attributes":{"allow-destroy-plan":true}}}' > /dev/null
  ok "Enabled destroy plan: $name"
}

# ── Helper: trigger destroy run and poll ─────────────────────────────────────
destroy_workspace() {
  local ws_id=$1 name=$2
  local resource_count
  resource_count=$(ws_resource_count "$ws_id")

  if [[ "$resource_count" -eq 0 ]]; then
    ok "$name — 0 resources, skipping destroy"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] Would trigger destroy on $name ($resource_count resources)"
    return 0
  fi

  info "Triggering destroy on $name ($resource_count resources)..."
  local run_id
  run_id=$(tfe POST "/runs" \
    "{\"data\":{\"attributes\":{\"message\":\"Teardown destroy — triggered by teardown-workspaces.sh\",\"is-destroy\":true,\"auto-apply\":true},\"type\":\"runs\",\"relationships\":{\"workspace\":{\"data\":{\"type\":\"workspaces\",\"id\":\"$ws_id\"}}}}}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('id',''))" 2>/dev/null)

  if [[ -z "$run_id" ]]; then
    fail "Failed to trigger destroy run on $name"
    ERRORS=$((ERRORS+1))
    return 1
  fi

  info "Run $run_id — polling for completion..."
  local status="" elapsed=0
  while true; do
    status=$(tfe GET "/runs/$run_id" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('attributes',{}).get('status',''))" 2>/dev/null)

    case "$status" in
      applied|planned_and_finished)
        ok "$name — destroyed (run: $run_id)"
        return 0
        ;;
      errored|canceled|force_canceled|discarded)
        fail "$name — destroy run $status (run: $run_id)"
        fail "Check: https://app.terraform.io/app/$ORG/workspaces/$name/runs/$run_id"
        ERRORS=$((ERRORS+1))
        return 1
        ;;
    esac

    elapsed=$((elapsed+15))
    printf "    [%ds] status: %s\r" "$elapsed" "$status"
    sleep 15
  done
}

# ── Helper: delete workspace ─────────────────────────────────────────────────
delete_workspace() {
  local ws_id=$1 name=$2
  local count
  count=$(ws_resource_count "$ws_id")

  if [[ "$count" -gt 0 ]]; then
    fail "Cannot delete $name — still has $count resources. Destroy must complete first."
    ERRORS=$((ERRORS+1))
    return 1
  fi

  [[ "$DRY_RUN" == "true" ]] && { info "[dry-run] Would delete $name"; return; }
  tfe DELETE "/workspaces/$ws_id" > /dev/null
  ok "Deleted workspace: $name"
}

# ── Discover workspaces ───────────────────────────────────────────────────────
echo -e "${BOLD}Discovering workspaces...${NC}"

# Determine naming pattern by checking which exists
WS_PREFIX="${CLIENT_ID}-${ENV}"
WS_SUFFIX_PREFIX="${CLIENT_ID}"

# Portal workspace is always <client>-<env>
PORTAL_NAME="${CLIENT_ID}-${ENV}"
PORTAL_ID=$(ws_id "$PORTAL_NAME")

# Bootstrap workspace is always bootstrap-<client>-<env>
BOOTSTRAP_NAME="bootstrap-${CLIENT_ID}-${ENV}"
BOOTSTRAP_ID=$(ws_id "$BOOTSTRAP_NAME")

# Service workspaces — detect naming pattern
declare -A SVC_IDS
declare -A SVC_NAMES
for svc in api rds secrets vpc secure-baseline; do
  # Try env-suffix pattern first: <client>-<service>-<env>
  name_suffix="${CLIENT_ID}-${svc}-${ENV}"
  id_suffix=$(ws_id "$name_suffix")
  # Fall back to env-infix pattern: <client>-<env>-<service>
  name_infix="${CLIENT_ID}-${ENV}-${svc}"
  id_infix=$(ws_id "$name_infix")

  if [[ -n "$id_suffix" ]]; then
    SVC_IDS[$svc]="$id_suffix"
    SVC_NAMES[$svc]="$name_suffix"
    ok "Found: $name_suffix ($id_suffix)"
  elif [[ -n "$id_infix" ]]; then
    SVC_IDS[$svc]="$id_infix"
    SVC_NAMES[$svc]="$name_infix"
    ok "Found: $name_infix ($id_infix)"
  else
    warn "Not found: $svc workspace (will skip)"
    SVC_IDS[$svc]=""
    SVC_NAMES[$svc]=""
  fi
done

[[ -n "$PORTAL_ID" ]]    && ok "Found: $PORTAL_NAME ($PORTAL_ID)" || warn "Not found: $PORTAL_NAME"
[[ -n "$BOOTSTRAP_ID" ]] && ok "Found: $BOOTSTRAP_NAME ($BOOTSTRAP_ID)" || warn "Not found: $BOOTSTRAP_NAME"
echo ""

# ── Step 1: Lock all workspaces ───────────────────────────────────────────────
echo -e "${BOLD}[1] Locking all workspaces...${NC}"
for svc in api rds secrets vpc secure-baseline; do
  [[ -n "${SVC_IDS[$svc]:-}" ]] && lock_workspace "${SVC_IDS[$svc]}" "${SVC_NAMES[$svc]}"
done
[[ -n "$PORTAL_ID" ]]    && lock_workspace "$PORTAL_ID"    "$PORTAL_NAME"
[[ -n "$BOOTSTRAP_ID" ]] && lock_workspace "$BOOTSTRAP_ID" "$BOOTSTRAP_NAME"
echo ""

# ── Step 2: Enable destroy plans on portal + service workspaces ───────────────
echo -e "${BOLD}[2] Enabling destroy plans...${NC}"
for svc in api rds secrets vpc secure-baseline; do
  [[ -n "${SVC_IDS[$svc]:-}" ]] && enable_destroy "${SVC_IDS[$svc]}" "${SVC_NAMES[$svc]}"
done
[[ -n "$PORTAL_ID" ]] && enable_destroy "$PORTAL_ID" "$PORTAL_NAME"
# bootstrap already has allow_destroy_plan=true — skip
echo ""

# ── Step 3: Destroy in dependency order ──────────────────────────────────────
echo -e "${BOLD}[3] Destroying workspaces in dependency order...${NC}"

echo "  Step 3a — api + rds (parallel)"
[[ -n "${SVC_IDS[api]:-}" ]]  && destroy_workspace "${SVC_IDS[api]}"  "${SVC_NAMES[api]}"  &
[[ -n "${SVC_IDS[rds]:-}" ]]  && destroy_workspace "${SVC_IDS[rds]}"  "${SVC_NAMES[rds]}"  &
wait
echo ""

echo "  Step 3b — secrets + vpc (parallel)"
[[ -n "${SVC_IDS[secrets]:-}" ]] && destroy_workspace "${SVC_IDS[secrets]}" "${SVC_NAMES[secrets]}" &
[[ -n "${SVC_IDS[vpc]:-}" ]]     && destroy_workspace "${SVC_IDS[vpc]}"     "${SVC_NAMES[vpc]}"     &
wait
echo ""

echo "  Step 3c — secure-baseline"
[[ -n "${SVC_IDS[secure-baseline]:-}" ]] && \
  destroy_workspace "${SVC_IDS[secure-baseline]}" "${SVC_NAMES[secure-baseline]}"
echo ""

echo "  Step 3d — portal workspace"
[[ -n "$PORTAL_ID" ]] && destroy_workspace "$PORTAL_ID" "$PORTAL_NAME"
echo ""

echo "  Step 3e — bootstrap workspace"
[[ -n "$BOOTSTRAP_ID" ]] && destroy_workspace "$BOOTSTRAP_ID" "$BOOTSTRAP_NAME"
echo ""

if [[ "$ERRORS" -gt 0 ]]; then
  fail "$ERRORS destroy step(s) failed. Fix errors before deleting workspaces."
  exit 1
fi

# ── Step 4: Delete all workspaces ─────────────────────────────────────────────
echo -e "${BOLD}[4] Deleting workspaces...${NC}"
for svc in api rds secrets vpc secure-baseline; do
  [[ -n "${SVC_IDS[$svc]:-}" ]] && delete_workspace "${SVC_IDS[$svc]}" "${SVC_NAMES[$svc]}"
done
[[ -n "$PORTAL_ID" ]]    && delete_workspace "$PORTAL_ID"    "$PORTAL_NAME"
[[ -n "$BOOTSTRAP_ID" ]] && delete_workspace "$BOOTSTRAP_ID" "$BOOTSTRAP_NAME"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}=== Summary ===${NC}"
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "${GREEN}✓ All workspaces destroyed and deleted.${NC}"
  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo "  1. Remove bootstrap-accounts-dev/accounts_${CLIENT_ID}.tf"
  echo "  2. Apply bootstrap-account-workspace-management-dev to clean control-plane state"
  echo ""
else
  echo -e "${RED}✗ $ERRORS error(s). Check output above.${NC}"
  exit 1
fi
