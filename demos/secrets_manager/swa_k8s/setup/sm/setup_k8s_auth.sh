#!/bin/bash
# shellcheck disable=SC2005,SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

printf "\n\nSetting local vars from env\n"
isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
sm_service_name=$SM_SERVICE_NAME
safe_name=$SAFE_NAME

printf "isp_id=%s\nisp_subdomain=%s\nclient_id=%s\nsm_service_name=%s\n" \
  "$isp_id" "$isp_subdomain" "$client_id" "$sm_service_name"

identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
printf "\nidentity_token obtained\n"

conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
printf "\nconjur_token obtained\n"

# ── 1. Load base workload policy branch ────────────────────────────────────
printf "\n\nLoading swa-workloads policy branch under data\n"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat swa-workloads.yaml)"

# ── 2. Load JWT authenticator policy ───────────────────────────────────────
printf "\n\nRendering and loading JWT authenticator policy\n"
resolve_template "authn-jwt-swa.tmpl.yaml" "authn-jwt-swa.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat authn-jwt-swa.yaml)"

# ── 3. Configure authenticator variables ───────────────────────────────────
printf "\n\nConfiguring authenticator variables for %s\n" "$sm_service_name"

# public-keys: inline JWKS from the Kubernetes cluster
auth_public_keys_id="conjur/authn-jwt/$sm_service_name/public-keys"
public_keys_value=$(jq -cn --argjson jwks "$K8S_PUBLIC_KEYS" '{type:"jwks", value:$jwks}')
apply_conjur_secret "$isp_subdomain" "$conjur_token" "$auth_public_keys_id" "$public_keys_value"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$sm_service_name/token-app-property" "sub"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$sm_service_name/identity-path" "data/swa-workloads"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$sm_service_name/issuer" "$(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)"

apply_conjur_secret "$isp_subdomain" "$conjur_token" \
  "conjur/authn-jwt/$sm_service_name/audience" "conjur"

# ── 4. Load workload host identity ─────────────────────────────────────────
printf "\n\nLoading SWA server workload identity\n"
resolve_template "workload-swa.tmpl.yaml" "workload-swa.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat workload-swa.yaml)"

# ── 5. Grant workload access to authenticator ──────────────────────────────
printf "\n\nGranting SWA server access to JWT authenticator\n"
resolve_template "add-to-authn.tmpl.yaml" "add-to-authn.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat add-to-authn.yaml)"

# ── 6. Grant workload access to safe ───────────────────────────────────────
printf "\n\nGranting SWA server access to safe %s\n" "$safe_name"
resolve_template "add-to-safe.tmpl.yaml" "add-to-safe.yaml"
apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat add-to-safe.yaml)"

# ── 7. Enable authenticator ────────────────────────────────────────────────
printf "\n\nEnabling authenticator authn-jwt/%s\n" "$sm_service_name"
activate_conjur_service "$isp_subdomain" "$conjur_token" "authn-jwt/$sm_service_name"

printf "\n\nSM setup complete\n"
printf "Authenticator endpoint: https://%s.secretsmgr.cyberark.cloud/api/authn-jwt/%s\n" \
  "$isp_subdomain" "$sm_service_name"
