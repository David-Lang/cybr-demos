#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

set_safe_managing_cpm() {
  # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 cpm_name
  if [ $# -ne 4 ]; then
    echo "Usage: set_safe_managing_cpm isp_subdomain identity_token safe_name cpm_name"
    return 1
  fi

  local safe_url_id
  safe_url_id="$(jq -nr --arg v "$3" '$v|@uri')"

  curl --silent --show-error \
    --request PUT \
    --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/${safe_url_id}/" \
    --header "Authorization: Bearer $2" \
    --header "Content-Type: application/json" \
    --data "{\"safeName\":\"$3\",\"managingCPM\":\"$4\"}" >/dev/null
}

main() {
  set_variables
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  printf "\n\nidentity_token acquired (redacted)\n"

  create_safe "$isp_subdomain" "$identity_token" "$safe_name"
  printf "Assigning Safe '%s' to CPM '%s'\n" "$safe_name" "$safe_managing_cpm"
  set_safe_managing_cpm "$isp_subdomain" "$identity_token" "$safe_name" "$safe_managing_cpm"
  add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"
  add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"

  create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"

  printf "\n\nconjur_isp_auth $isp_subdomain identity_token\n"
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
  printf "\n\nconjur_token acquired (redacted)\n"

  printf "Waiting for synchronizer (*/$safe_name/delegation/consumers)\n"
  wait_for_synchronizer "$isp_subdomain" "$conjur_token" "$safe_name"
}

# shellcheck disable=SC2153
set_variables() {
  printf "\nSetting local vars from Env"
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET
  safe_name=$SAFE_NAME
  safe_managing_cpm="${SAFE_MANAGING_CPM:-PasswordManager}"
}

main "$@"
