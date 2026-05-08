#!/bin/bash
# shellcheck disable=SC2005,SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
swa_env="$demo_path/setup/swa/swa_registered.env"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
if [[ -f "$swa_env" ]]; then
  source "$swa_env"
else
  echo "[ERROR] $swa_env not found. Run setup/swa/setup.sh first." >&2
  exit 1
fi
SWA_SM_SERVICE_NAME="${SM_SERVICE_NAME}-swa"
set +a

: "${SWA_OIDC_ISSUER:?SWA_OIDC_ISSUER is not set in swa_registered.env}"
: "${SWA_WORKLOAD_SPIFFE_ID:?SWA_WORKLOAD_SPIFFE_ID is not set in vars.env}"

printf "\n\nSetting local vars from env\n"
isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name=$SAFE_NAME

printf "isp_id=%s\nisp_subdomain=%s\nclient_id=%s\nswa_sm_service_name=%s\n" \
  "$isp_id" "$isp_subdomain" "$client_id" "$SWA_SM_SERVICE_NAME"
printf "swa_oidc_issuer=%s\nworkload_spiffe_id=%s\n" "$SWA_OIDC_ISSUER" "$SWA_WORKLOAD_SPIFFE_ID"

identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
printf "\nidentity_token obtained\n"

conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
printf "\nconjur_token obtained\n"

# ── 1. Ensure base workload policy branch exists ───────────────────────────
printf "\n\nLoading swa-workloads policy branch under data\n"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat swa-workloads.yaml)"

# ── 2. Load JWT-SVID authenticator policy ──────────────────────────────────
printf "\n\nRendering and loading SWA JWT-SVID authenticator policy\n"
resolve_template "authn-jwt-swa-svid.tmpl.yaml" "authn-jwt-swa-svid.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat authn-jwt-swa-svid.yaml)"

# ── 3. Configure authenticator variables ───────────────────────────────────
printf "\n\nConfiguring authenticator variables for %s\n" "$SWA_SM_SERVICE_NAME"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$SWA_SM_SERVICE_NAME/jwks-uri" "$SWA_OIDC_ISSUER/.well-known/jwks"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$SWA_SM_SERVICE_NAME/token-app-property" "sub"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$SWA_SM_SERVICE_NAME/identity-path" "data/swa-workloads"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$SWA_SM_SERVICE_NAME/issuer" "$SWA_OIDC_ISSUER"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$SWA_SM_SERVICE_NAME/audience" "conjur"

# ── 4. Load giftapp-swa workload host identity ─────────────────────────────
printf "\n\nLoading giftapp-swa workload identity\n"
resolve_template "workload-swa-svid.tmpl.yaml" "workload-swa-svid.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat workload-swa-svid.yaml)"

# Reuse grant templates by exporting the SWA authenticator and SPIFFE subject.
export SM_SERVICE_NAME="$SWA_SM_SERVICE_NAME"
export JWT_CLAIM_IDENTITY_VALUE="$SWA_WORKLOAD_SPIFFE_ID"

# ── 5. Grant workload access to authenticator ──────────────────────────────
printf "\n\nGranting giftapp-swa access to JWT-SVID authenticator\n"
resolve_template "add-to-authn.tmpl.yaml" "add-to-authn-swa.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat add-to-authn-swa.yaml)"

# ── 6. Grant workload access to safe ───────────────────────────────────────
printf "\n\nGranting giftapp-swa access to safe %s\n" "$safe_name"
resolve_template "add-to-safe.tmpl.yaml" "add-to-safe-swa.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat add-to-safe-swa.yaml)"

# ── 7. Enable authenticator ────────────────────────────────────────────────
printf "\n\nEnabling authenticator authn-jwt/%s\n" "$SWA_SM_SERVICE_NAME"
activate_conjur_service "$isp_subdomain" "$conjur_token" "authn-jwt/$SWA_SM_SERVICE_NAME"

printf "\n\nSWA JWT-SVID authenticator setup complete\n"
printf "Authenticator endpoint: https://%s.secretsmgr.cyberark.cloud/api/authn-jwt/%s\n" \
  "$isp_subdomain" "$SWA_SM_SERVICE_NAME"
