#!/bin/bash
# Register SWA control-plane objects (trust domain, server group, node group, server)
# in Conjur Cloud via the bundled terraform-provider-swa. Idempotent (terraform apply).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init
swa_release_paths

tf_dir="$demo_path/setup/swa/terraform"

if ! command -v terraform >/dev/null 2>&1; then
  echo "[ERROR] terraform not found on PATH. Install Terraform (>= 1.5)." >&2
  exit 1
fi
if [[ ! -f "$SWA_TFRC" ]]; then
  echo "[ERROR] Provider mirror not staged. Run setup/swa/load_release.sh first." >&2
  exit 1
fi

echo "[INFO] Acquiring Conjur token for the SWA provider"
swa_get_tokens

# The SWA provider authenticates via conjur-api-go using these env vars.
# get_conjur_token returns a base64-encoded token; the provider expects the
# decoded JSON access token.
export CONJUR_APPLIANCE_URL="https://${SM_FQDN}/api"
export CONJUR_ACCOUNT="conjur"
CONJUR_AUTHN_TOKEN="$(printf '%s' "$SWA_CONJUR_TOKEN" | base64 --decode)"
export CONJUR_AUTHN_TOKEN
export TF_CLI_CONFIG_FILE="$SWA_TFRC"

echo "[INFO] Reading cluster OIDC JWKS (for the server's inline public_keys)"
cluster_jwks="$(kubectl get --raw /openid/v1/jwks)"
[[ -n "$cluster_jwks" ]] || { echo "[ERROR] empty cluster JWKS from /openid/v1/jwks" >&2; exit 1; }

# Issuer: prefer the live token 'iss' if the server SA exists; otherwise default.
cluster_issuer="https://kubernetes.default.svc.cluster.local"
if kubectl get sa "$SWA_SERVER_SA" -n "$SWA_NAMESPACE" >/dev/null 2>&1; then
  tok="$(kubectl create token "$SWA_SERVER_SA" -n "$SWA_NAMESPACE" --audience "$SWA_CONTROL_PLANE_AUDIENCE" --duration 60s 2>/dev/null || true)"
  if [[ -n "$tok" ]]; then
    iss="$(printf '%s' "$tok" | cut -d. -f2 | { p="$(cat)"; pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s%*s' "$p" "$pad" '' | tr ' ' '='; } | base64 --decode 2>/dev/null | jq -r '.iss' 2>/dev/null || true)"
    [[ -n "$iss" && "$iss" != "null" ]] && cluster_issuer="$iss"
  fi
fi
echo "[INFO] cluster issuer: $cluster_issuer"

cat > "$tf_dir/terraform.tfvars" <<EOF
trust_domain    = "${SWA_TRUST_DOMAIN}"
server_group    = "${SWA_SERVER_GROUP}"
node_group      = "${SWA_NODE_GROUP}"
cluster_name    = "${SWA_CLUSTER_NAME}"
agent_namespace = "${SWA_NAMESPACE}"
agent_sa        = "${SWA_AGENT_SA}"
server_sa       = "${SWA_SERVER_SA}"
server_audience = "${SWA_CONTROL_PLANE_AUDIENCE}"
cluster_issuer  = "${cluster_issuer}"
jwt_signature_algorithm = "${SWA_TD_JWT_ALG}"
jwt_signing_key_type    = "${SWA_TD_JWT_KEY_TYPE}"
EOF
# JWKS written separately so JSON quoting survives.
{
  printf 'cluster_jwks = '
  printf '%s' "$cluster_jwks" | jq -Rs .
  printf '\n'
} >> "$tf_dir/terraform.tfvars"

echo "[INFO] terraform init"
terraform -chdir="$tf_dir" init -input=false >/dev/null

echo "[INFO] terraform apply"
terraform -chdir="$tf_dir" apply -input=false -auto-approve

# Persist outputs for downstream stages (server install reads server_authn_id).
authn_id="$(terraform -chdir="$tf_dir" output -raw server_authn_id)"
{
  echo "SWA_SERVER_AUTHN_ID=$authn_id"
  echo "SWA_SERVER_ADDRESS=$(terraform -chdir="$tf_dir" output -raw server_address)"
} > "$tf_dir/swa_outputs.env"
echo "[INFO] SWA objects registered. Outputs -> $tf_dir/swa_outputs.env"
