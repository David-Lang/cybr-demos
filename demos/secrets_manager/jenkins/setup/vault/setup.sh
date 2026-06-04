#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/jenkins"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"

main() {
  set_variables
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  printf "\nidentity_token acquired (redacted)\n"

  create_safe "$isp_subdomain" "$identity_token" "$safe_name"
  add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"
  add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"
  create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"

  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
  printf "Waiting for synchronizer (*/$safe_name/delegation/consumers)\n"
  wait_for_synchronizer "$isp_subdomain" "$conjur_token" "$safe_name"
  printf "\nVault setup complete.\n"
}

set_variables() {
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET
  safe_name=$SAFE_NAME
}

main "$@"
