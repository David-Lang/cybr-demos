#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/jenkins"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"

main() {
  set_variables

  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")

  resolve_template "remove_jenkins_jwt_apps_revoke.tmpl.yaml" "remove_jenkins_jwt_apps_revoke.yaml"
  patch_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt/${CONJUR_JWT_AUTHN_ID}" "$(cat remove_jenkins_jwt_apps_revoke.yaml)"

  resolve_template "remove_jenkins_apps_vault_revoke.tmpl.yaml" "remove_jenkins_apps_vault_revoke.yaml"
  patch_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat remove_jenkins_apps_vault_revoke.yaml)"

  patch_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat remove_workloads.yaml)"
  patch_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat remove_auth_service.yaml)"

  printf "\nConjur remove complete.\n"
}

set_variables() {
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET

  if [ -z "${JWT_CLAIM_IDENTITY:-}" ] || [ -z "${SAFE_NAME:-}" ]; then
    printf "JWT_CLAIM_IDENTITY and SAFE_NAME must be set (same as setup/vars.env).\n" >&2
    exit 1
  fi
}

main "$@"
