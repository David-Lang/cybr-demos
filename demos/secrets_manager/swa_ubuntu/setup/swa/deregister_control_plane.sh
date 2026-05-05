#!/bin/bash
# deregister_control_plane.sh — Delete SWA control plane resources via the SWA REST API
# and clean up the orphaned Conjur JWT authenticator policy.
#
# Run before re-running register_control_plane.sh, or when tearing down a lab.
# Deletes in reverse dependency order: server → node group → server group → trust domain.
# Also removes the orphaned Conjur JWT authenticator left behind by the SWA backend
# (a known SWA backend issue where DELETE does not clean up Conjur policy).
#
# Prerequisites:
#   - CYBR_DEMOS_PATH set
#   - jq and curl in PATH

# shellcheck disable=SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTERED_ENV="$SCRIPT_DIR/swa_registered.env"

# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/conjur_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$DEMO_DIR/setup/vars.env"

SWA_SERVER_GROUP_NAME="${SWA_RESOURCE_PREFIX}-server-group"
SWA_SERVER_NAME="${SWA_RESOURCE_PREFIX}-server"

SWA_API="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api/swa"

echo "=========================================="
echo "SWA Control Plane Deregistration"
echo "=========================================="
echo ""
echo "  Tenant:       $TENANT_SUBDOMAIN"
echo "  Trust domain: $SWA_TRUST_DOMAIN_NAME"
echo "  Server group: $SWA_SERVER_GROUP_NAME"
echo "  Node group:   $SWA_NODE_GROUP_NAME"
echo ""

# --- Authenticate ---
echo "[1/2] Authenticating to Conjur..."
isp_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$isp_token")
echo "      OK"
echo ""

# --- Helper: SWA DELETE, treats 404 as OK (already gone) ---
swa_delete() {
  local path="$1"
  local tmp_out; tmp_out=$(mktemp)
  local http_status
  http_status=$(curl -sS -o "$tmp_out" -w "%{http_code}" -X DELETE \
    "${SWA_API}${path}" \
    -H "Authorization: Token token=\"${conjur_token}\"" \
    -H "Accept: application/x.secretsmgr.v2+json")
  local response; response=$(cat "$tmp_out"); rm -f "$tmp_out"
  if [ "$http_status" = "404" ]; then
    echo "      (already gone)"
    return 0
  fi
  if [[ "$http_status" -lt 200 || "$http_status" -ge 300 ]]; then
    printf "      WARNING: DELETE %s returned HTTP %s: %s\n" "$path" "$http_status" "$response" >&2
    return 1
  fi
}

# --- Step 2: Delete all resources ---
echo "[2/2] Deleting SWA resources and cleaning up Conjur policy..."
echo ""

# 2a. Delete server
printf "  Deleting server: %s..." "$SWA_SERVER_NAME"
swa_delete "/trust-domains/${SWA_TRUST_DOMAIN_NAME}/server-groups/${SWA_SERVER_GROUP_NAME}/components/${SWA_SERVER_NAME}"
echo "      OK"

# 2b. Clean up orphaned Conjur JWT authenticator
# The SWA backend deletes the SWA-side server record but leaves the Conjur JWT
# authenticator policy behind. We explicitly delete it here to prevent 409 on re-registration.
SERVER_AUTH_NAME=""
if [ -f "$REGISTERED_ENV" ]; then
  # shellcheck disable=SC1090
  source "$REGISTERED_ENV"
  SERVER_AUTH_NAME=$(printf '%s' "${SWA_SERVER_LOGIN_URL:-}" | base64 -d 2>/dev/null | \
    grep -o 'authn-jwt/[^/]*' | head -1 | sed 's|authn-jwt/||')
fi

if [ -n "$SERVER_AUTH_NAME" ]; then
  printf "  Cleaning Conjur authenticator policy: authn-jwt/%s..." "$SERVER_AUTH_NAME"
  PATCH_RESULT=$(patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-jwt" \
    "- !delete
  record: !policy ${SERVER_AUTH_NAME}" 2>/dev/null || echo "FAILED")
  if echo "$PATCH_RESULT" | grep -q "FAILED\|error\|Error"; then
    printf "\n      WARNING: could not delete Conjur authenticator policy (may need manual cleanup)\n" >&2
    printf "      Delete 'authn-jwt/%s' from: Secrets Manager → Secure Workload Access\n" "$SERVER_AUTH_NAME" >&2
  else
    echo "      OK"
  fi
else
  echo "  Skipping Conjur authenticator cleanup (swa_registered.env not found or login_url missing)"
  echo "  If re-registration fails with 409, manually delete the authenticator from the admin console."
fi
echo ""

# 2c. Delete node group
printf "  Deleting node group: %s..." "$SWA_NODE_GROUP_NAME"
swa_delete "/trust-domains/${SWA_TRUST_DOMAIN_NAME}/server-groups/${SWA_SERVER_GROUP_NAME}/node-groups/${SWA_NODE_GROUP_NAME}"
echo "      OK"

# 2d. Delete server group
printf "  Deleting server group: %s..." "$SWA_SERVER_GROUP_NAME"
swa_delete "/trust-domains/${SWA_TRUST_DOMAIN_NAME}/server-groups/${SWA_SERVER_GROUP_NAME}"
echo "      OK"

# 2e. Delete trust domain
printf "  Deleting trust domain: %s..." "$SWA_TRUST_DOMAIN_NAME"
swa_delete "/trust-domains/${SWA_TRUST_DOMAIN_NAME}"
echo "      OK"

# 2f. Clean up orphaned Conjur trust domain policy.
# The SWA backend leaves the Conjur policy at data/swa/trust-domains/{name} behind
# on DELETE, causing 409 on re-registration with the same trust domain name.
printf "  Cleaning Conjur trust domain policy: data/swa/trust-domains/%s..." "$SWA_TRUST_DOMAIN_NAME"
TD_PATCH_RESULT=$(patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data/swa/trust-domains" \
  "- !delete
  record: !policy ${SWA_TRUST_DOMAIN_NAME}" 2>/dev/null || echo "FAILED")
if echo "$TD_PATCH_RESULT" | grep -q "FAILED\|error\|Error"; then
  printf "\n      WARNING: could not delete Conjur trust domain policy (may need manual cleanup)\n" >&2
  printf "      Delete 'data/swa/trust-domains/%s' from: Secrets Manager → Secure Workload Access\n" "$SWA_TRUST_DOMAIN_NAME" >&2
else
  echo "      OK"
fi
echo ""

rm -f "$REGISTERED_ENV"
echo "  Removed: $REGISTERED_ENV"
echo ""
echo "=========================================="
echo "Deregistration complete."
echo ""
echo "Next: bash setup/swa/register_control_plane.sh"
echo "=========================================="
