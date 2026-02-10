#!/bin/bash
set -euo pipefail

source "$HOME/cybrlab/demos/demo_vars.env.sh"
source "$HOME/cybrlab/demos/demo_vars.env.sh"

main() {
  set_variables
  create_cert
  setup_safe
  setup_app_id
}

# shellcheck disable=SC2153
set_variables() {
  demo_path="$CYBR_DEMOS_PATH/demos/credential_providers/ccp_ubuntu"

  # Set environment variables using .env file
  # -a means that every bash variable would become an environment variable
  # Using ‘+’ rather than ‘-’ causes the option to be turned off
  set -a
  source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
  source "$demo_path/setup/vars.env"
  set +a

  tenant_id=$TENANT_ID
  tenant_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET

  ccp_app1_id="$CCP_APP1_ID"
  ccp_app2_id="$CCP_APP2_ID"
  safe_name="$SAFE_NAME"
}

setup_safe() {
  identity_token=$(get_identity_token "$tenant_id" "$client_id" "$client_secret")

  create_safe "$tenant_subdomain" "$identity_token" "$safe_name"
  add_safe_admin_role "$tenant_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"

  create_account_ssh_user_1 "$tenant_subdomain" "$identity_token" "$safe_name"

  ## Have to get CCP App ProvIDs
  #echo "Adding Provider $prov_id to safe $safe_name"
  #add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$prov_id"
}

setup_apps() {
  create_app "$tenant_subdomain" "$identity_token" "$cp_app_id"

  # App Network Auth
  #add_app_authentication "$tenant_subdomain" "$identity_token" "$cp_app_id" "Path" "$demo_path/app1.sh"

  # App Cert Auth
  #add_app_authentication "$tenant_subdomain" "$identity_token" "$cp_app_id" "Path" "$demo_path/app1.sh"

  echo "Adding AppId $ccp_app1_id to safe $safe_name"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$ccp_app1_id"

  echo "Adding AppId $ccp_app2_id to safe $safe_name"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$ccp_app2_id"

}

create_cert() {
  setup/create_app_crt.sh
  setup/get_serial_number.sh
  serialNumber=$(cat cert_serial_number)
}

main "$@"
