#!/usr/bin/env bash
# =============================================================================
# pre-flight-check.sh — Run before onboarding any new client to an AWS account
#
# Usage:
#   ./bootstrap/pre-flight-check.sh [--account-id <id>] [--client-id <id>] [--env <env>]
#
# What it does:
#   Checks for existing singleton AWS resources that would conflict with a new
#   secure-baseline deployment. Prints a recommended secure-baseline config
#   block with the correct enable_* overrides for the new client.
#
# Prerequisites:
#   - AWS CLI authenticated to the target account
#   - jq installed
#
# Exit codes:
#   0 = all clear (new account, no conflicts)
#   1 = conflicts detected (check output for recommended overrides)
#   2 = usage error or missing dependencies
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
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
ACCOUNT_ID=""
CLIENT_ID="new-client"
ENV="dev"

while [[ $# -gt 0 ]]; do
  case $1 in
    --account-id) ACCOUNT_ID="$2"; shift 2 ;;
    --client-id)  CLIENT_ID="$2";  shift 2 ;;
    --env)        ENV="$2";        shift 2 ;;
    --help|-h)
      sed -n '/^# Usage/,/^# Exit/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

# ── Dependency checks ─────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
  echo "Error: aws CLI not found" >&2; exit 2
fi
if ! command -v jq &>/dev/null; then
  echo "Error: jq not found. Install with: brew install jq" >&2; exit 2
fi

# ── Resolve current account if not supplied ───────────────────────────────────
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
if [[ -z "$CURRENT_ACCOUNT" ]]; then
  echo "Error: Could not determine AWS account. Check credentials." >&2; exit 2
fi

if [[ -n "$ACCOUNT_ID" && "$ACCOUNT_ID" != "$CURRENT_ACCOUNT" ]]; then
  echo -e "${RED}Error:${NC} --account-id $ACCOUNT_ID does not match current credentials (account $CURRENT_ACCOUNT)" >&2
  exit 2
fi
ACCOUNT_ID="$CURRENT_ACCOUNT"

REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

echo ""
echo -e "${BOLD}=== HCP Terraform Pre-Flight Check ===${NC}"
echo -e "  Account : ${BOLD}${ACCOUNT_ID}${NC}"
echo -e "  Region  : ${BOLD}${REGION}${NC}"
echo -e "  Client  : ${BOLD}${CLIENT_ID}${NC} (env: ${ENV})"
echo ""

CONFLICTS=0
OVERRIDES=()

# ── 1. IAM OIDC Provider (app.terraform.io) ───────────────────────────────────
echo -e "${BOLD}[1] OIDC Provider (app.terraform.io)${NC}"
OIDC_ARN=$(aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[?ends_with(Arn, `/app.terraform.io`)].Arn' \
  --output text 2>/dev/null || true)

if [[ -n "$OIDC_ARN" ]]; then
  warn "Exists: $OIDC_ARN"
  info  "CFN deploy: add  ExistingOIDCProviderArn=$OIDC_ARN"
  OVERRIDES+=("ExistingOIDCProviderArn=$OIDC_ARN")
  CONFLICTS=$((CONFLICTS + 1))
else
  ok "Not found — CFN will create it"
fi
echo ""

# ── 2. TerraformDeployRole ────────────────────────────────────────────────────
echo -e "${BOLD}[2] TerraformDeployRole${NC}"
ROLE_EXISTS=$(aws iam get-role --role-name TerraformDeployRole \
  --query 'Role.RoleName' --output text 2>/dev/null || true)

if [[ -n "$ROLE_EXISTS" ]]; then
  ROLE_STACK=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query "StackSummaries[?contains(StackName,'terraform-bootstrap')].StackName" \
    --output text 2>/dev/null | tr '\t' '\n' | head -1 || true)
  warn "Role exists (owned by stack: ${ROLE_STACK:-unknown})"
  info  "Update the EXISTING stack instead of creating a new one"
  info  "Existing role already trusts all workspaces in bootstrap-dev + team-dev (project-scoped)"
  CONFLICTS=$((CONFLICTS + 1))
else
  ok "Not found — CFN will create it"
fi
echo ""

# ── 3. IAM Access Analyzer (ACCOUNT type) ────────────────────────────────────
echo -e "${BOLD}[3] IAM Access Analyzer (ACCOUNT type)${NC}"
ANALYZERS=$(aws accessanalyzer list-analyzers \
  --query 'analyzers[?type==`ACCOUNT`].name' \
  --output text 2>/dev/null || true)

if [[ -n "$ANALYZERS" ]]; then
  warn "Exists: $ANALYZERS"
  info  "Add to secure-baseline config:  enable_access_analyzer = false"
  OVERRIDES+=("enable_access_analyzer = false")
  CONFLICTS=$((CONFLICTS + 1))
else
  ok "Not found — secure-baseline will create it"
fi
echo ""

# ── 4. GuardDuty Detector ─────────────────────────────────────────────────────
echo -e "${BOLD}[4] GuardDuty Detector${NC}"
DETECTORS=$(aws guardduty list-detectors --query 'DetectorIds' --output text 2>/dev/null || true)

if [[ -n "$DETECTORS" ]]; then
  warn "Exists: $DETECTORS"
  info  "Add to secure-baseline config:  enable_guardduty = false"
  OVERRIDES+=("enable_guardduty = false")
  CONFLICTS=$((CONFLICTS + 1))
else
  ok "Not found — secure-baseline will create it"
fi
echo ""

# ── 5. Security Hub ───────────────────────────────────────────────────────────
echo -e "${BOLD}[5] Security Hub${NC}"
SECHUB=$(aws securityhub describe-hub --query 'HubArn' --output text 2>/dev/null || true)

if [[ -n "$SECHUB" && "$SECHUB" != "None" ]]; then
  warn "Enabled: $SECHUB"
  info  "Add to secure-baseline config:  enable_security_hub = false"
  OVERRIDES+=("enable_security_hub = false")
  CONFLICTS=$((CONFLICTS + 1))
else
  ok "Not enabled — secure-baseline will enable it"
fi
echo ""

# ── 6. AWS Config Recorder ────────────────────────────────────────────────────
echo -e "${BOLD}[6] AWS Config Recorder${NC}"
CONFIG_RECORDERS=$(aws configservice describe-configuration-recorders \
  --query 'ConfigurationRecorders[*].name' --output text 2>/dev/null || true)

if [[ -n "$CONFIG_RECORDERS" ]]; then
  warn "Exists: $CONFIG_RECORDERS"
  info  "Add to secure-baseline config:  enable_config = false"
  OVERRIDES+=("enable_config = false")
  CONFLICTS=$((CONFLICTS + 1))
else
  ok "Not found — secure-baseline will create it"
fi
echo ""

# ── 7. CloudTrail (informational — multiple trails are allowed) ───────────────
echo -e "${BOLD}[7] CloudTrail Trails (informational — not a singleton)${NC}"
TRAILS=$(aws cloudtrail list-trails --query 'Trails[*].Name' --output text 2>/dev/null || true)
TRAIL_COUNT=$(echo "$TRAILS" | wc -w | tr -d ' ')

if [[ "$TRAIL_COUNT" -gt 0 ]]; then
  info "Existing trails ($TRAIL_COUNT): $TRAILS"
  info "AWS allows up to 5 trails per region — new client trail will be created"
  ok   "No conflict (new trail: ${CLIENT_ID}-${ENV}-trail)"
else
  ok "No trails — secure-baseline will create one"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}=== Summary ===${NC}"

if [[ "$CONFLICTS" -eq 0 ]]; then
  echo -e "${GREEN}✓ No conflicts. This is a clean account — use standard deploy.${NC}"
  exit 0
fi

echo -e "${YELLOW}⚠  $CONFLICTS conflict(s) detected.${NC}"
echo ""
echo -e "${BOLD}Recommended secure-baseline config block for ${CLIENT_ID}-${ENV}:${NC}"
echo ""
echo '  "secure-baseline" = {'
echo '    kms_key_arn = local.kms_key_arn'
for override in "${OVERRIDES[@]}"; do
  # Only print secure-baseline flags (not CFN params)
  if [[ "$override" == enable_* ]]; then
    echo "    $override"
  fi
done
echo '  }'
echo ""

CFN_OVERRIDES=()
for override in "${OVERRIDES[@]}"; do
  if [[ "$override" == ExistingOIDCProviderArn* ]]; then
    CFN_OVERRIDES+=("    $override \\")
  fi
done

if [[ "${#CFN_OVERRIDES[@]}" -gt 0 ]]; then
  echo -e "${BOLD}Recommended CFN deploy parameters:${NC}"
  echo ""
  echo "  aws cloudformation deploy \\"
  echo "    --stack-name hcp-terraform-bootstrap-<existing-stack-name> \\"
  echo "    --template-file bootstrap/cfn-terraform-bootstrap.yaml \\"
  echo "    --capabilities CAPABILITY_NAMED_IAM \\"
  echo "    --parameter-overrides \\"
  for p in "${CFN_OVERRIDES[@]}"; do echo "$p"; done
  echo "    HCPOrganization=core-aws \\"
  echo "    HCPBootstrapProject=bootstrap-${ENV} \\"
  echo "    HCPTeamProject=team-${ENV} \\"
  echo "    KMSAliasName=alias/<account-nickname>-platform"
  echo ""
fi

echo -e "See ${BOLD}docs/runbooks/cfn-oidc-bootstrap.md${NC} for full onboarding steps."
echo ""
exit 1
