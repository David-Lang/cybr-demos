#!/bin/bash
# register_control_plane.sh — Register SWA trust domain, server group, server, and node group
# with the CyberArk Secrets Manager control plane via Terraform.
#
# Run once before setup.sh (or re-run to update).
# Outputs: setup/swa/swa_registered.env — sourced by setup.sh and install_server.sh
#
# Prerequisites:
#   - CYBR_DEMOS_PATH set
#   - SWA Terraform provider installed: bash setup/swa/install_tf_provider.sh
#   - terraform in PATH
#   - jq in PATH

# shellcheck disable=SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
OUT_ENV="$SCRIPT_DIR/swa_registered.env"

# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/conjur_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$DEMO_DIR/setup/vars.env"

echo "=========================================="
echo "SWA Control Plane Registration"
echo "=========================================="
echo ""
echo "  Tenant:           $TENANT_SUBDOMAIN"
echo "  Trust domain:     $SWA_TRUST_DOMAIN_NAME"
echo "  Resource prefix:  $SWA_RESOURCE_PREFIX"
echo "  Node group:       $SWA_NODE_GROUP_NAME"
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
for cmd in terraform jq openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "ERROR: '%s' not found in PATH\n" "$cmd" >&2
    exit 1
  fi
done

# --- Step 1: Authenticate to Conjur ---
echo "[1/5] Authenticating to Conjur..."
isp_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$isp_token")
CONJUR_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"

# Decode the sub claim (UUID) from the ISP token — this is what Conjur sees as the JWT subject,
# and it differs from CLIENT_ID (which is the username/email used to obtain the token).
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
echo "[2/5] Generating x509pop CA and agent certs..."
bash "$SCRIPT_DIR/gen_x509pop_ca.sh" "$SWA_NODE_GROUP_NAME"
echo ""

# --- Step 3: Install Terraform provider (idempotent) ---
echo "[3/5] Installing SWA Terraform provider..."
if [ -f "$SCRIPT_DIR/install_tf_provider.sh" ]; then
  bash "$SCRIPT_DIR/install_tf_provider.sh"
else
  echo "      WARNING: install_tf_provider.sh not found — assuming provider is already installed"
fi
echo ""

# --- Step 4: Run Terraform ---
echo "[4/5] Running Terraform (trust domain + server group + server + node group)..."
echo ""

cd "$TF_DIR"

terraform init -input=false -upgrade 2>&1 | grep -E "(Initializing|provider|Warning|Error)" || true
echo ""

TF_APPLY_OUT=$(mktemp)
if ! terraform apply -input=false -auto-approve \
  -var="conjur_url=${CONJUR_URL}" \
  -var="conjur_token=${conjur_token}" \
  -var="trust_domain_name=${SWA_TRUST_DOMAIN_NAME}" \
  -var="resource_prefix=${SWA_RESOURCE_PREFIX}" \
  -var="node_group_name=${SWA_NODE_GROUP_NAME}" \
  -var="ca_certificate_path=${SCRIPT_DIR}/x509pop_ca.pem" \
  -var="tenant_id=${TENANT_ID}" \
  -var="client_id=${CLIENT_ID}" \
  -var="client_subject=${ISP_SUB}" 2>&1 | tee "$TF_APPLY_OUT"; then

  if grep -q "conjur_resource_already_exists\|already exists" "$TF_APPLY_OUT" 2>/dev/null; then
    printf "\nERROR: Conjur JWT authenticator naming conflict (SWA provider cleanup bug).\n" >&2
    printf "       The previous server's authenticator was not removed when terraform destroyed it.\n" >&2
    printf "       Options:\n" >&2
    printf "         1. Change SWA_RESOURCE_PREFIX in setup/vars.env (e.g. swa-demo2) to use a fresh name.\n" >&2
    printf "         2. Manually delete the stale authenticator in the CyberArk admin console,\n" >&2
    printf "            then re-run: bash setup/swa/register_control_plane.sh\n" >&2
  fi
  rm -f "$TF_APPLY_OUT"
  exit 1
fi
rm -f "$TF_APPLY_OUT"

echo ""

# --- Step 5: Extract outputs and write swa_registered.env ---
echo "[5/5] Extracting Terraform outputs..."
terraform output -json > /tmp/swa_tf_outputs.json

TRUST_DOMAIN_ID=$(jq -r '.trust_domain_id.value'   /tmp/swa_tf_outputs.json)
OIDC_ISSUER_URL=$(jq -r '.oidc_issuer_url.value'   /tmp/swa_tf_outputs.json)
SERVER_LOGIN_URL=$(jq -r '.server_login_url.value'  /tmp/swa_tf_outputs.json)
TD_NAME=$(jq -r '.trust_domain_name.value'          /tmp/swa_tf_outputs.json)
NG_NAME=$(jq -r '.node_group_name.value'            /tmp/swa_tf_outputs.json)
SPIFFE_PREFIX=$(jq -r '.spiffe_id_prefix.value'     /tmp/swa_tf_outputs.json)

rm -f /tmp/swa_tf_outputs.json

cat > "$OUT_ENV" <<EOF
# Generated by register_control_plane.sh — do not edit manually
export SWA_TRUST_DOMAIN_ID="${TRUST_DOMAIN_ID}"
export SWA_TRUST_DOMAIN_NAME="${TD_NAME}"
export SWA_OIDC_ISSUER="${OIDC_ISSUER_URL}"
export SWA_SERVER_LOGIN_URL="${SERVER_LOGIN_URL}"
export SWA_NODE_GROUP_NAME="${NG_NAME}"
export SWA_SPIFFE_PREFIX="${SPIFFE_PREFIX}"
export SWA_X509POP_CA_CERT="${SCRIPT_DIR}/x509pop_ca.pem"
export SWA_X509POP_AGENT_CERT="${SCRIPT_DIR}/x509pop_agent.pem"
export SWA_X509POP_AGENT_KEY="${SCRIPT_DIR}/x509pop_agent.key"
EOF

echo ""
echo "  Trust domain ID:  $TRUST_DOMAIN_ID"
echo "  OIDC issuer:      $OIDC_ISSUER_URL"
echo "  Server login URL: $(echo "$SERVER_LOGIN_URL" | base64 -d 2>/dev/null || echo "$SERVER_LOGIN_URL")"
echo "  SPIFFE prefix:    $SPIFFE_PREFIX"
echo ""
echo "  Written: $OUT_ENV"
echo ""
echo "=========================================="
echo "Registration complete."
echo ""
echo "Next: bash setup/swa/install_server.sh"
echo "=========================================="
