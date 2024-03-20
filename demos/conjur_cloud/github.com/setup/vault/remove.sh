#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/isp_vars.env.sh"

main() {
  set_variables
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  printf "\n\nidentity_token: \n$identity_token\n"

  delete_safe "$isp_subdomain" "identity_token" "$safe_name"

  delete_account_ssh_user_1 "$isp_subdomain" "identity_token" "$safe_name"

}

# shellcheck disable=SC2153
set_variables() {
  printf "\nSetting local vars from Env"
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET
  safe_name=$SAFE_NAME
}

main "$@"
