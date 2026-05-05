#!/bin/bash
# deregister_control_plane.sh — Tear down SWA control plane resources via Terraform.
#
# Run this before re-running register_control_plane.sh to clean up a previous deployment.
# Note: if register_control_plane.sh fails with a 409 naming conflict after running this,
# the SWA Terraform provider did not fully clean up its Conjur resources. In that case,
# change SWA_RESOURCE_PREFIX in setup/vars.env (e.g. swa-demo2) before re-registering.
#
# Prerequisites:
#   - CYBR_DEMOS_PATH set
#   - terraform in PATH  |  jq in PATH

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
echo "SWA Control Plane Deregistration"
echo "=========================================="
echo ""

# --- Step 1: Authenticate to Conjur ---
echo "[1/2] Authenticating to Conjur..."
isp_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$isp_token")
CONJUR_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
ISP_SUB=$(printf '%s' "$isp_token" | cut -d. -f2 | tr '_-' '/+' | \
  awk '{n=length($0)%4; if(n==2) print $0"=="; else if(n==3) print $0"="; else print $0}' | \
  base64 -d 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["sub"])' 2>/dev/null || echo "")
echo "      OK"
echo ""

# --- Step 2: Terraform destroy ---
echo "[2/2] Running terraform destroy..."

cd "$TF_DIR"

if [ ! -f "terraform.tfstate" ]; then
  echo "  No terraform.tfstate — nothing to destroy."
elif [ "$(jq '.resources | length' terraform.tfstate 2>/dev/null || echo 0)" == "0" ]; then
  echo "  Terraform state is already empty — skipping destroy."
else
  # CA cert is needed by terraform to evaluate file() during plan/destroy
  CA_CERT="${SCRIPT_DIR}/x509pop_ca.pem"
  if [ ! -f "$CA_CERT" ]; then
    echo "  x509pop_ca.pem not found — generating for destroy..."
    bash "$SCRIPT_DIR/gen_x509pop_ca.sh" "${SWA_NODE_GROUP_NAME}" 2>/dev/null || true
  fi

  terraform destroy -input=false -auto-approve \
    -var="conjur_url=${CONJUR_URL}" \
    -var="conjur_token=${conjur_token}" \
    -var="trust_domain_name=${SWA_TRUST_DOMAIN_NAME}" \
    -var="resource_prefix=${SWA_RESOURCE_PREFIX}" \
    -var="node_group_name=${SWA_NODE_GROUP_NAME}" \
    -var="ca_certificate_path=${CA_CERT}" \
    -var="tenant_id=${TENANT_ID}" \
    -var="client_id=${CLIENT_ID}" \
    -var="client_subject=${ISP_SUB:-}" 2>&1 || \
    echo "  NOTE: Destroy completed with warnings — some Conjur resources may remain (known SWA provider cleanup bug)."
fi

rm -f "$OUT_ENV"
echo "  Removed: $OUT_ENV"
echo ""
echo "=========================================="
echo "Deregistration complete."
echo ""
echo "Next: bash setup/swa/register_control_plane.sh"
echo "=========================================="
