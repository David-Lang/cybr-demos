#!/bin/bash
# shellcheck disable=SC2005
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

main() {
  set_variables

  # Authenticate Service User
  printf "\n\nplatform_auth $isp_id $client_id $client_secret\n"
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  printf "\n\nidentity_token: \n$identity_token\n"

  printf "\n\nconjur_isp_auth $isp_subdomain identity_token\n"
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
  printf "\n\nconjur_token: \n$conjur_token\n"

  printf "\n\nresolve_template remove_github_jwt_apps_revoke.tmpl.yaml remove_github_jwt_apps_revoke.yaml\n"
  resolve_template "remove_github_jwt_apps_revoke.tmpl.yaml" "remove_github_jwt_apps_revoke.yaml"

  patch_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt/github" "$(cat remove_github_jwt_apps_revoke.yaml)"

  printf "\n\nresolve_template remove_github_apps_vault_revoke.tmpl.yaml remove_github_apps_vault_revoke.yaml\n"
  resolve_template "remove_github_apps_vault_revoke.tmpl.yaml" "remove_github_apps_vault_revoke.yaml"

  patch_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat remove_github_apps_vault_revoke.yaml)"

  patch_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat remove_workloads.yaml)"

  patch_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat remove_auth_service.yaml)"

  printf "\n"
}

# shellcheck disable=SC2153
set_variables() {
  printf "\nSetting local vars from Env"
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET
  github_workflow=$GITHUB_WORKFLOW
  if [ -z "${SAFE_NAME:-}" ] || [ -z "${github_workflow:-}" ]; then
    printf "SAFE_NAME and GITHUB_WORKFLOW must be set (same as setup/vars.env) for revoke template.\n" >&2
    exit 1
  fi
}

main "$@"
