#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Source utilities and variables ---
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/conjur_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup/vars.env"

echo "=========================================="
echo "Setup: SWA Ubuntu"
echo "=========================================="
echo ""

# --- Validate required tenant vars ---
required_vars=(TENANT_ID TENANT_SUBDOMAIN CLIENT_ID CLIENT_SECRET)
for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name:-}" ] || [[ "${!var_name}" == SET_* ]]; then
    echo "ERROR: $var_name is not set. Update demos/tenant_vars.sh." >&2
    exit 1
  fi
done

# --- Validate SWA_MODE ---
if [[ "$SWA_MODE" != "mock" && "$SWA_MODE" != "real" ]]; then
  echo "ERROR: SWA_MODE must be 'mock' or 'real'. Got: $SWA_MODE" >&2
  exit 1
fi

echo "SWA_MODE:            $SWA_MODE"
echo "TENANT_SUBDOMAIN:    $TENANT_SUBDOMAIN"
echo "CONJUR_JWT_SERVICE_ID: $CONJUR_JWT_SERVICE_ID"
echo "SWA_WORKLOAD_ID:     $SWA_WORKLOAD_ID"
echo ""

# --- Step 1: Authenticate to Conjur ---
echo "[1/6] Authenticating to Conjur..."
identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")
echo "      Conjur token acquired   OK"
echo ""

# --- Step 2: Apply Conjur policies ---
echo "[2/6] Applying Conjur policies..."
echo "      Applying authenticator_consumers.yaml to branch: data"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(cat "$SCRIPT_DIR/setup/conjur_policy/authenticator_consumers.yaml")"

echo "      Applying jwt_auth.yml to branch: conjur/authn-jwt"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-jwt" \
  "$(cat "$SCRIPT_DIR/setup/conjur_policy/jwt_auth.yml")"

echo "      Applying workload_identity.yml to branch: data"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(cat "$SCRIPT_DIR/setup/conjur_policy/workload_identity.yml")"
echo "      Policies applied   OK"
echo ""

# --- Step 3: Configure JWT authenticator variables ---
echo "[3/6] Configuring JWT authenticator (swa1)..."

BASE="conjur/authn-jwt/${CONJUR_JWT_SERVICE_ID}"

if [[ "$SWA_MODE" == "mock" ]]; then
  echo "      Mode: mock — generating keys and embedding public-keys in Conjur"
  MOCK_KEYS_SCRIPT="$SCRIPT_DIR/setup/swa/gen_mock_keys.sh"
  MOCK_KEY_DIR="$SCRIPT_DIR/setup/swa"
  bash "$MOCK_KEYS_SCRIPT"
  public_keys_json=$(cat "$MOCK_KEY_DIR/mock_jwks.json")
  apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
    "${BASE}/public-keys" "$public_keys_json"
  apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
    "${BASE}/issuer" "$SWA_MOCK_ISSUER"
else
  # real mode
  if [[ "$SWA_OIDC_ISSUER" == "INPUT_REQUIRED" ]]; then
    echo "ERROR: SWA_OIDC_ISSUER must be set in setup/vars.env when SWA_MODE=real" >&2
    echo "       TODO(Q4): Confirm OIDC issuer URL format from SWA documentation." >&2
    exit 1
  fi
  echo "      Mode: real — configuring jwks-uri from SWA OIDC discovery"
  jwks_uri="${SWA_OIDC_ISSUER}/.well-known/jwks"
  apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
    "${BASE}/jwks-uri" "$jwks_uri"
  apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
    "${BASE}/issuer" "$SWA_OIDC_ISSUER"
fi

apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
  "${BASE}/token-app-property" "sub"

apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
  "${BASE}/identity-path" "data/workloads/swa"

apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
  "${BASE}/audience" "conjur"

echo "      JWT authenticator configured   OK"
echo ""

# --- Step 4: Activate JWT authenticator ---
echo "[4/6] Activating JWT authenticator (authn-jwt/${CONJUR_JWT_SERVICE_ID})..."
activate_conjur_service "$TENANT_SUBDOMAIN" "$conjur_token" \
  "authn-jwt/${CONJUR_JWT_SERVICE_ID}"
echo "      Authenticator activated   OK"
echo ""

# --- Step 5: Create demo secret ---
echo "[5/6] Creating demo secret (${DEMO_SECRET_ID})..."
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
  "$DEMO_SECRET_ID" "$DEMO_SECRET_VALUE"
echo "      Demo secret created   OK"
echo ""

# --- Step 6: SWA binary installation placeholder ---
echo "[6/6] SWA binary installation..."
if [[ "$SWA_MODE" == "mock" ]]; then
  echo "      Mode: mock — skipping SWA binary install"
  echo "      Mock agent: $SCRIPT_DIR/setup/swa/mock_agent.sh"
  echo "      Set SWA_AGENT_BIN=$SCRIPT_DIR/setup/swa/mock_agent.sh in your environment"
else
  echo ""
  echo "  TODO: Install SWA binaries manually before continuing."
  echo ""
  echo "  Required steps (complete when binaries are available):"
  echo "    1. Copy swa-server to /opt/swa/bin/swa-server"
  echo "    2. Copy swa-agent  to /opt/swa/bin/swa-agent"
  echo "    3. chmod +x /opt/swa/bin/swa-server /opt/swa/bin/swa-agent"
  echo "    4. Configure setup/swa/server.conf  (see needs-info #16)"
  echo "    5. Configure setup/swa/agent.conf   (see needs-info #17)"
  echo "    6. Start SWA Server: sudo systemctl start swa-server"
  echo "    7. Start SWA Agent:  sudo systemctl start swa-agent"
  echo "    8. Verify agent attestation before running demo.sh"
  echo ""
fi

echo "=========================================="
echo "Setup complete."
echo ""
echo "Next steps:"
if [[ "$SWA_MODE" == "mock" ]]; then
  echo "  export SWA_AGENT_BIN=$SCRIPT_DIR/setup/swa/mock_agent.sh"
fi
echo "  bash ./demo.sh"
echo "=========================================="
