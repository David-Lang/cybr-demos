#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
OUT_ENV="$SCRIPT_DIR/swa_registered.env"

trust_domain_id=$(terraform -chdir="$TF_DIR" output -raw trust_domain_id)
trust_domain_name=$(terraform -chdir="$TF_DIR" output -raw trust_domain_name)
oidc_issuer_url=$(terraform -chdir="$TF_DIR" output -raw oidc_issuer_url)
server_login_url=$(terraform -chdir="$TF_DIR" output -raw server_login_url)
node_group_name=$(terraform -chdir="$TF_DIR" output -raw node_group_name)
spiffe_prefix=$(terraform -chdir="$TF_DIR" output -raw spiffe_id_prefix)

cat > "$OUT_ENV" <<EOF
# Runtime SWA registration settings; do not edit manually
export SWA_TRUST_DOMAIN_ID="${trust_domain_id}"
export SWA_TRUST_DOMAIN_NAME="${trust_domain_name}"
export SWA_OIDC_ISSUER="${oidc_issuer_url}"
export SWA_SERVER_LOGIN_URL="${server_login_url}"
export SWA_NODE_GROUP_NAME="${node_group_name}"
export SWA_SPIFFE_PREFIX="${spiffe_prefix}"
EOF

echo "[INFO] wrote $OUT_ENV"
