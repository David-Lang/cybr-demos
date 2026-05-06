#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

printf "\nSetting local vars from env\n"
isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name=$SAFE_NAME

printf "\nisp_id=%s\nisp_subdomain=%s\nclient_id=%s\n" "$isp_id" "$isp_subdomain" "$client_id"

identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
printf "\nidentity_token obtained\n"

create_safe "$isp_subdomain" "$identity_token" "$safe_name"
add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"
add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"

# Create giftapp-api-key account (value syncs to data/vault/$SAFE_NAME/giftapp-api-key/password)
printf "\nCreating giftapp-api-key account in safe %s\n" "$safe_name"
curl --silent --location \
  "https://$isp_subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts" \
  --header "Authorization: Bearer $identity_token" \
  --header "Content-Type: application/json" \
  --data '{
    "name":         "giftapp-api-key",
    "address":      "giftapp",
    "userName":     "api-key",
    "platformId":   "UnixSSH",
    "safeName":     "'"$safe_name"'",
    "secretType":   "password",
    "secret":       "'"${GIFTAPP_API_KEY:-APPSECRETxfindme}"'"
  }' | jq -r '.id // "already exists or error"'

# Create giftapp-db-pass account (value syncs to data/vault/$SAFE_NAME/giftapp-db-pass/password)
printf "\nCreating giftapp-db-pass account in safe %s\n" "$safe_name"
curl --silent --location \
  "https://$isp_subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts" \
  --header "Authorization: Bearer $identity_token" \
  --header "Content-Type: application/json" \
  --data '{
    "name":         "giftapp-db-pass",
    "address":      "giftapp",
    "userName":     "db-pass",
    "platformId":   "UnixSSH",
    "safeName":     "'"$safe_name"'",
    "secretType":   "password",
    "secret":       "'"${DB_PASS:-Cyberark1}"'"
  }' | jq -r '.id // "already exists or error"'

conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
printf "\nWaiting for synchronizer (*/$safe_name/delegation/consumers)\n"
wait_for_synchronizer "$isp_subdomain" "$conjur_token" "$safe_name"
printf "\nSafe and secrets are synchronized to Conjur\n"
