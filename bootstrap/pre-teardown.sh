#!/usr/bin/env bash
# =============================================================================
# pre-teardown.sh — Run BEFORE triggering Terraform destroy on any workspace
#
# Usage:
#   ./bootstrap/pre-teardown.sh --client-id <id> --env <env>
#
# What it does:
#   Deletes AWS resources that TerraformDeployRole cannot destroy due to the
#   DenyAuditTamper explicit deny in TerraformDeployPolicy:
#     - CloudTrail trail (cloudtrail:DeleteTrail is explicitly denied)
#     - S3 logging bucket (force_destroy=false)
#     - Config recorder / delivery channel (ONLY if no other clients share account)
#     - GuardDuty detector (ONLY if no other clients share account)
#
#   SHARED ACCOUNT SAFETY: Config and GuardDuty are account-level singletons.
#   If other clients in the same account have enable_config=false or
#   enable_guardduty=false, they are relying on this client's resources for
#   account-wide security monitoring. The script will REFUSE to delete these
#   singletons when other client trails exist in the account, to prevent
#   disabling audit/threat detection for remaining clients.
#
# Prerequisites:
#   - AWS CLI authenticated with admin/root credentials (NOT TerraformDeployRole)
#   - jq installed
#
# Exit codes:
#   0 = all pre-teardown steps completed (safe to trigger Terraform destroy)
#   1 = one or more steps failed or blocked
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

while [[ $# -gt 0 ]]; do
  case $1 in
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --env)       ENV="$2";       shift 2 ;;
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

# ── Dependency checks ────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then echo "Error: aws CLI not found" >&2; exit 2; fi
if ! command -v jq &>/dev/null;  then echo "Error: jq not found" >&2; exit 2; fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
if [[ -z "$ACCOUNT_ID" ]]; then
  echo "Error: Could not determine AWS account. Check credentials." >&2; exit 2
fi

REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
NAME_PREFIX="${CLIENT_ID}-${ENV}"
ERRORS=0

echo ""
echo -e "${BOLD}=== Pre-Teardown Cleanup: ${NAME_PREFIX} ===${NC}"
echo -e "  Account : ${BOLD}${ACCOUNT_ID}${NC}"
echo -e "  Region  : ${BOLD}${REGION}${NC}"
echo ""
echo -e "${YELLOW}WARNING: Use admin credentials — not TerraformDeployRole.${NC}"
echo -e "${YELLOW}Run this BEFORE triggering Terraform destroy.${NC}"
echo ""

# ── Shared account detection ─────────────────────────────────────────────────
# Count CloudTrail trails from OTHER clients in this account.
# Each client creates its own trail (<client>-<env>-trail), so other trails
# indicate other clients still rely on the account-level singletons.
OTHER_TRAILS=$(aws cloudtrail list-trails \
  --query "Trails[?Name!='${NAME_PREFIX}-trail'].Name" \
  --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" | wc -l | tr -d ' ')

if [[ "$OTHER_TRAILS" -gt 0 ]]; then
  SHARED_ACCOUNT=true
  warn "Shared account detected — ${OTHER_TRAILS} other client trail(s) found."
  info "Config and GuardDuty singletons will NOT be deleted (other clients depend on them)."
else
  SHARED_ACCOUNT=false
  ok "No other client trails found — sole client in this account."
fi
echo ""

# ── 1. CloudTrail trail ───────────────────────────────────────────────────────
echo -e "${BOLD}[1] CloudTrail Trail (client-specific — always safe to delete)${NC}"
TRAIL_EXISTS=$(aws cloudtrail get-trail --name "${NAME_PREFIX}-trail" \
  --query 'Trail.Name' --output text 2>/dev/null || true)

if [[ -n "$TRAIL_EXISTS" ]]; then
  info "Found: ${NAME_PREFIX}-trail"
  aws cloudtrail delete-trail --name "${NAME_PREFIX}-trail" 2>/dev/null && \
    ok "Deleted ${NAME_PREFIX}-trail" || \
    { fail "Failed to delete ${NAME_PREFIX}-trail"; ERRORS=$((ERRORS+1)); }
else
  ok "Not found — nothing to do"
fi
echo ""

# ── 2. S3 logging bucket (force_destroy=false) ───────────────────────────────
echo -e "${BOLD}[2] S3 Logging Bucket (client-specific — always safe to delete)${NC}"
BUCKET="${NAME_PREFIX}-logs-${ACCOUNT_ID}"
BUCKET_EXISTS=$(aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null && echo "yes" || echo "no")

if [[ "$BUCKET_EXISTS" == "yes" ]]; then
  info "Found: $BUCKET — emptying all versions..."
  python3 - <<PYEOF
import subprocess, json

bucket = "$BUCKET"
deleted = 0
while True:
    result = subprocess.run(
        ['aws','s3api','list-object-versions','--bucket',bucket,'--max-items','1000'],
        capture_output=True, text=True
    )
    data = json.loads(result.stdout) if result.stdout else {}
    objects = (data.get('Versions') or []) + (data.get('DeleteMarkers') or [])
    if not objects:
        break
    payload = json.dumps({'Objects': [{'Key': o['Key'], 'VersionId': o['VersionId']} for o in objects], 'Quiet': True})
    subprocess.run(['aws','s3api','delete-objects','--bucket',bucket,'--delete',payload], capture_output=True)
    deleted += len(objects)
    if not data.get('IsTruncated'):
        break
print(f"  Deleted {deleted} object versions/markers")
PYEOF
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null && \
    ok "Deleted $BUCKET" || \
    { fail "Failed to delete $BUCKET"; ERRORS=$((ERRORS+1)); }
else
  ok "Not found — nothing to do"
fi
echo ""

# ── 3. Config recorder + delivery channel (SINGLETON — shared account safe) ──
echo -e "${BOLD}[3] AWS Config Recorder (account singleton)${NC}"
CONFIG_RECORDER=$(aws configservice describe-configuration-recorders \
  --query "ConfigurationRecorders[?contains(name,'${NAME_PREFIX}')].name" \
  --output text 2>/dev/null || true)

if [[ -n "$CONFIG_RECORDER" ]]; then
  if [[ "$SHARED_ACCOUNT" == "true" ]]; then
    warn "SKIPPED — shared account: other clients rely on Config for account monitoring."
    warn "Transfer ownership by setting enable_config=true in another client's secure-baseline"
    warn "and applying before tearing down ${CLIENT_ID}."
    ERRORS=$((ERRORS+1))
  else
    info "Found recorder: $CONFIG_RECORDER"
    aws configservice stop-configuration-recorder \
      --configuration-recorder-name "$CONFIG_RECORDER" 2>/dev/null && \
      ok "Stopped recorder: $CONFIG_RECORDER" || \
      { fail "Failed to stop recorder: $CONFIG_RECORDER"; ERRORS=$((ERRORS+1)); }
    aws configservice delete-delivery-channel \
      --delivery-channel-name "${NAME_PREFIX}-config-channel" 2>/dev/null && \
      ok "Deleted delivery channel: ${NAME_PREFIX}-config-channel" || \
      { fail "Failed to delete delivery channel: ${NAME_PREFIX}-config-channel — Terraform destroy will fail on config:DeleteDeliveryChannel"; ERRORS=$((ERRORS+1)); }
    aws configservice delete-configuration-recorder \
      --configuration-recorder-name "$CONFIG_RECORDER" 2>/dev/null && \
      ok "Deleted recorder: $CONFIG_RECORDER" || \
      { fail "Failed to delete recorder: $CONFIG_RECORDER"; ERRORS=$((ERRORS+1)); }
  fi
else
  ok "Not found — nothing to do"
fi
echo ""

# ── 4. GuardDuty detector (SINGLETON — shared account safe) ──────────────────
echo -e "${BOLD}[4] GuardDuty Detector (account singleton)${NC}"
DETECTORS=$(aws guardduty list-detectors --query 'DetectorIds' --output text 2>/dev/null || true)

if [[ -n "$DETECTORS" ]]; then
  for det_id in $DETECTORS; do
    TAG_VAL=$(aws guardduty list-tags-for-resource \
      --resource-arn "arn:aws:guardduty:${REGION}:${ACCOUNT_ID}:detector/${det_id}" \
      --query "Tags.ClientId" --output text 2>/dev/null || true)
    if [[ "$TAG_VAL" == "$CLIENT_ID" ]]; then
      if [[ "$SHARED_ACCOUNT" == "true" ]]; then
        warn "SKIPPED — shared account: other clients rely on GuardDuty for threat detection."
        warn "Transfer ownership by setting enable_guardduty=true in another client's"
        warn "secure-baseline and applying before tearing down ${CLIENT_ID}."
        ERRORS=$((ERRORS+1))
      else
        info "Found detector for $CLIENT_ID: $det_id"
        aws guardduty delete-detector --detector-id "$det_id" 2>/dev/null && \
          ok "Deleted detector: $det_id" || \
          { fail "Failed to delete detector: $det_id"; ERRORS=$((ERRORS+1)); }
      fi
    fi
  done
else
  ok "Not found — nothing to do"
fi
echo ""

# ── 5. Security Hub (SINGLETON — always manual) ───────────────────────────────
echo -e "${BOLD}[5] Security Hub (account singleton — manual only)${NC}"
warn "Security Hub is account-level and cannot be safely automated."
info "If this is the last client in the account and you want to disable it:"
info "  aws securityhub disable-security-hub"
ok "No automated action taken"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}=== Summary ===${NC}"
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "${GREEN}✓ Pre-teardown complete. Safe to proceed.${NC}"
else
  echo -e "${RED}✗ $ERRORS issue(s) require manual resolution before Terraform destroy.${NC}"
  echo -e "  See warnings above."
  echo ""
  exit 1
fi

echo ""
echo -e "${BOLD}Next step — enable destroy plans, then trigger in order:${NC}"
echo "  See docs/runbooks/client-teardown.md for the full procedure."
echo ""
exit 0
