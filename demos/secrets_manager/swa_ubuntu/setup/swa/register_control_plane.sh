#!/bin/bash
# register_control_plane.sh — Register SWA trust domain, server group, node group, and server
# directly via the CyberArk SWA REST API (no Terraform).
#
# Run once before setup.sh (or re-run after deregister_control_plane.sh).
# Outputs: setup/swa/swa_registered.env — sourced by setup.sh and install_server.sh
#
# Prerequisites:
#   - CYBR_DEMOS_PATH set
#   - jq in PATH
#   - openssl in PATH

# shellcheck disable=SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_ENV="$SCRIPT_DIR/swa_registered.env"

# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/conjur_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$DEMO_DIR/setup/vars.env"

# Derived resource names (same convention as the old Terraform config)
SWA_SERVER_GROUP_NAME="${SWA_RESOURCE_PREFIX}-server-group"
SWA_SERVER_NAME="${SWA_RESOURCE_PREFIX}-server"

SWA_API="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api/swa"
CONJUR_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
CA_CERT_PATH="$SCRIPT_DIR/x509pop_ca.pem"

echo "=========================================="
echo "SWA Control Plane Registration"
echo "=========================================="
echo ""
echo "  Tenant:       $TENANT_SUBDOMAIN"
echo "  Trust domain: $SWA_TRUST_DOMAIN_NAME"
echo "  Server group: $SWA_SERVER_GROUP_NAME"
echo "  Node group:   $SWA_NODE_GROUP_NAME"
echo ""

# --- Validate required vars ---
required_vars=(TENANT_ID TENANT_SUBDOMAIN CLIENT_ID CLIENT_SECRET
               SWA_TRUST_DOMAIN_NAME SWA_RESOURCE_PREFIX SWA_NODE_GROUP_NAME)
for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name:-}" ] || [[ "${!var_name}" == SET_* ]] || [[ "${!var_name}" == INPUT_REQUIRED ]]; then
    printf "ERROR: %s is not set in tenant_vars.sh or setup/vars.env\n" "$var_name" >&2
    exit 1
  fi
done

# --- Check dependencies ---
for cmd in jq openssl curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "ERROR: '%s' not found in PATH\n" "$cmd" >&2
    exit 1
  fi
done

# --- Helper: SWA API call, exits on non-2xx unless caller passes allow_status ---
# Usage: swa_call METHOD path [body_json]
# Returns response body; HTTP status is checked and causes exit on failure.
swa_call() {
  local method="$1" path="$2" body="${3:-}"
  local tmp_out; tmp_out=$(mktemp)
  local http_status
  if [ -n "$body" ]; then
    http_status=$(curl -sS -o "$tmp_out" -w "%{http_code}" -X "$method" \
      "${SWA_API}${path}" \
      -H "Authorization: Token token=\"${conjur_token}\"" \
      -H "Accept: application/x.secretsmgr.v2+json" \
      -H "Content-Type: application/json" \
      --data "$body")
  else
    http_status=$(curl -sS -o "$tmp_out" -w "%{http_code}" -X "$method" \
      "${SWA_API}${path}" \
      -H "Authorization: Token token=\"${conjur_token}\"" \
      -H "Accept: application/x.secretsmgr.v2+json")
  fi
  local response; response=$(cat "$tmp_out"); rm -f "$tmp_out"
  if [[ "$http_status" -lt 200 || "$http_status" -ge 300 ]]; then
    printf "ERROR: SWA API %s %s returned HTTP %s\n" "$method" "$path" "$http_status" >&2
    printf "Response: %s\n" "$response" >&2
    return 1
  fi
  printf '%s' "$response"
}

# --- Step 1: Authenticate ---
echo "[1/6] Authenticating to Conjur..."
isp_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$isp_token")

ISP_SUB=$(printf '%s' "$isp_token" | cut -d. -f2 | tr '_-' '/+' | \
  awk '{n=length($0)%4; if(n==2) print $0"=="; else if(n==3) print $0"="; else print $0}' | \
  base64 -d 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["sub"])' 2>/dev/null)

if [ -z "$ISP_SUB" ]; then
  echo "ERROR: could not decode sub claim from ISP token" >&2
  exit 1
fi
echo "      ISP token sub: $ISP_SUB"
echo "      OK"
echo ""

# --- Step 2: Generate x509pop certs ---
echo "[2/6] Generating x509pop CA and agent certs..."
bash "$SCRIPT_DIR/gen_x509pop_ca.sh" "$SWA_NODE_GROUP_NAME"
echo ""

# --- Step 3: Create trust domain ---
echo "[3/6] Creating trust domain: $SWA_TRUST_DOMAIN_NAME..."
TD_BODY=$(jq -n \
  --arg name "$SWA_TRUST_DOMAIN_NAME" \
  '{
    name: $name,
    jwt: {
      signature_algorithm: "RS256",
      signing_key_type: "RSA_2048",
      signing_key_ttl: 86400,
      token_ttl: 600
    }
  }')
swa_call POST "/trust-domains" "$TD_BODY" > /dev/null
echo "      OK"
echo ""

# --- Step 4: Create server group (x509pop node attestation) ---
echo "[4/6] Creating server group: $SWA_SERVER_GROUP_NAME..."
CA_CERT_CONTENT=$(cat "$CA_CERT_PATH")
SG_BODY=$(jq -n \
  --arg name "$SWA_SERVER_GROUP_NAME" \
  --arg ca_cert "$CA_CERT_CONTENT" \
  '{
    name: $name,
    description: "",
    node_attestation: {
      x509pop: {
        ca_certificates: $ca_cert
      }
    }
  }')
swa_call POST "/trust-domains/${SWA_TRUST_DOMAIN_NAME}/server-groups" "$SG_BODY" > /dev/null
echo "      OK"
echo ""

# --- Step 5: Create node group ---
echo "[5/6] Creating node group: $SWA_NODE_GROUP_NAME..."
NG_BODY=$(jq -n \
  --arg name "$SWA_NODE_GROUP_NAME" \
  '{
    name: $name,
    description: "",
    workload_type: "unix",
    workload_configuration: {
      spiffe_id_template: "spiffe://{{ .trustdomain }}/{{ .nodegroup }}/workload/{{ .unix.user }}",
      workload_registration_policies: ["unix.user != '\''root'\''"]
    }
  }')
swa_call POST \
  "/trust-domains/${SWA_TRUST_DOMAIN_NAME}/server-groups/${SWA_SERVER_GROUP_NAME}/node-groups" \
  "$NG_BODY" > /dev/null
echo "      OK"
echo ""

# --- Step 6: Register SWA server ---
echo "[6/6] Registering SWA server: $SWA_SERVER_NAME..."
SRV_BODY=$(jq -n \
  --arg name "$SWA_SERVER_NAME" \
  --arg sub "$ISP_SUB" \
  --arg tenant_id "$TENANT_ID" \
  '{
    name: $name,
    authentication: {
      type: "JWT",
      data: {
        sub: $sub,
        issuer: ("https://" + $tenant_id + ".id.cyberark.cloud/__idaptive_cybr_user_oidc/"),
        jwks_uri: ("https://" + $tenant_id + ".id.cyberark.cloud/OAuth2/Keys/__idaptive_cybr_user_oidc"),
        audience: "__idaptive_cybr_user_oidc"
      }
    }
  }')
SRV_RESPONSE=$(swa_call POST \
  "/trust-domains/${SWA_TRUST_DOMAIN_NAME}/server-groups/${SWA_SERVER_GROUP_NAME}/components" \
  "$SRV_BODY")

SERVER_LOGIN_URL=$(printf '%s' "$SRV_RESPONSE" | jq -r '.login_url // empty')
if [ -z "$SERVER_LOGIN_URL" ]; then
  echo "ERROR: server registration response did not contain login_url" >&2
  printf "Response: %s\n" "$SRV_RESPONSE" >&2
  exit 1
fi

# Activate the Conjur JWT authenticator created by the server registration.
# The SWA backend creates the policy and variables but does NOT enable it.
SERVER_AUTH_SVC=$(printf '%s' "$SERVER_LOGIN_URL" | base64 -d 2>/dev/null | \
  grep -o 'authn-jwt/[^/]*' | head -1)
if [ -n "$SERVER_AUTH_SVC" ]; then
  activate_conjur_service "$TENANT_SUBDOMAIN" "$conjur_token" "$SERVER_AUTH_SVC" > /dev/null
  echo "      Activated Conjur authenticator: $SERVER_AUTH_SVC"
else
  echo "      WARNING: could not extract authenticator service ID from login URL" >&2
fi
echo "      OK"
echo ""

# --- Write swa_registered.env ---
OIDC_ISSUER_URL="https://api.venafi.cloud/swa/v1/issuers/${SWA_TRUST_DOMAIN_NAME}"
SPIFFE_PREFIX="spiffe://${SWA_TRUST_DOMAIN_NAME}/${SWA_NODE_GROUP_NAME}"

cat > "$OUT_ENV" <<EOF
# Generated by register_control_plane.sh — do not edit manually
export SWA_TRUST_DOMAIN_ID="${SWA_TRUST_DOMAIN_NAME}"
export SWA_TRUST_DOMAIN_NAME="${SWA_TRUST_DOMAIN_NAME}"
export SWA_OIDC_ISSUER="${OIDC_ISSUER_URL}"
export SWA_SERVER_LOGIN_URL="${SERVER_LOGIN_URL}"
export SWA_NODE_GROUP_NAME="${SWA_NODE_GROUP_NAME}"
export SWA_SPIFFE_PREFIX="${SPIFFE_PREFIX}"
export SWA_X509POP_CA_CERT="${SCRIPT_DIR}/x509pop_ca.pem"
export SWA_X509POP_AGENT_CERT="${SCRIPT_DIR}/x509pop_agent.pem"
export SWA_X509POP_AGENT_KEY="${SCRIPT_DIR}/x509pop_agent.key"
EOF

echo "  Trust domain:     $SWA_TRUST_DOMAIN_NAME"
echo "  OIDC issuer:      $OIDC_ISSUER_URL"
echo "  Server login URL: $(printf '%s' "$SERVER_LOGIN_URL" | base64 -d 2>/dev/null || printf '%s' "$SERVER_LOGIN_URL")"
echo "  SPIFFE prefix:    $SPIFFE_PREFIX"
echo ""
echo "  Written: $OUT_ENV"
echo ""
echo "=========================================="
echo "Registration complete."
echo ""
echo "Next: bash setup.sh"
echo "=========================================="
