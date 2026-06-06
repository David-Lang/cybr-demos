#!/bin/bash
set -euo pipefail

main() {
  set_variables
  create_cert
  setup_safe
  setup_apps
}

# shellcheck disable=SC2153
set_variables() {
  demo_path="$CYBR_DEMOS_PATH/demos/credential_providers/rest_api_ubuntu"

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
  ccp_app3_id="$CCP_APP3_ID"
  safe_name="$SAFE_NAME"
  cert_issuer_json="$CERT_ISSUER_JSON"
  cert_san_json="$CERT_SAN_JSON"
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
  create_app "$tenant_subdomain" "$identity_token" "$ccp_app1_id"
  create_app "$tenant_subdomain" "$identity_token" "$ccp_app2_id"
  create_app "$tenant_subdomain" "$identity_token" "$ccp_app3_id"

  # App Network Auth
  client_ip=$(curl --silent "https://checkip.amazonaws.com/" | tr -d '[:space:]')
  if [ -n "$client_ip" ]; then
    add_app_authentication "$tenant_subdomain" "$identity_token" "$ccp_app1_id" "machineAddress" "$client_ip"
  else
    printf "\nWARNING: Could not determine public client IP for %s machineAddress authentication.\n" "$ccp_app1_id" >&2
  fi

  # App Cert Serial Number Auth
  add_app_authentication "$tenant_subdomain" "$identity_token" "$ccp_app2_id" "certificate" "$serial_number"

  # App Cert Attribute Auth: issuer and Subject Alternative Name values remain stable through renewal.
  add_app_certificate_issuer_san_auth "$tenant_subdomain" "$identity_token" "$ccp_app3_id" "$cert_issuer_json" "$cert_san_json"

  echo "Adding AppId $ccp_app1_id to safe $safe_name"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$ccp_app1_id"

  echo "Adding AppId $ccp_app2_id to safe $safe_name"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$ccp_app2_id"

  echo "Adding AppId $ccp_app3_id to safe $safe_name"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$ccp_app3_id"

}

create_cert() {
  "$demo_path/setup/create_app_crt.sh"
  "$demo_path/setup/get_serial_number.sh"
  serial_number=$(cat cert_serial_number)
}

add_app_certificate_issuer_san_auth() {
  # $1 isp_subdomain, $2 identity_token, $3 app_id, $4 issuer_json_array, $5 san_json_array
  printf "\nAdding certificateattr issuer and SAN auth to Application: %s\n" "$3"

  curl --silent \
    --request POST \
    --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/WebServices/PIMServices.svc/Applications/$3/Authentications/" \
    --header "Authorization: Bearer $2" \
    --header "Content-Type: application/json" \
    --data "{
      \"authentication\": {
        \"AuthType\": \"certificateattr\",
        \"Issuer\": $4,
        \"SubjectAlternativeName\": $5
      }
    }"
}

main "$@"
