#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/isp_vars.env.sh"

main() {
  set_variables
  platform_auth "$client_id" "$client_secret"
  create_safe "$safe_name"
  add_safe_member "$safe_name" "Conjur Sync"
  create_account_ssh_user_1 "$safe_name"
  wait_for_synchronizer
}

# shellcheck disable=SC2153
set_variables() {
  echo
  echo "Setting local vars from Env"
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET
  safe_name=$SAFE_NAME

}

platform_auth() {
  # $1 client_id, $2 client_secret
  echo
  echo "ISP Auth"

  identity_token=$(curl --location "https://$isp_id.id.cyberark.cloud/oauth2/platformtoken" \
  --header 'X-IDAP-NATIVE-CLIENT: true' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_id=$1" \
  --data-urlencode "client_secret=$2" | jq -r .access_token)

  echo "identity_token: $identity_token"
}

create_safe() {
  # $1 safe_name
  echo
  echo "Creating Safe: $1"

  curl --location "https://$isp_subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Safes" \
  --header "Authorization: Bearer $identity_token" \
  --header 'Content-Type: application/json' \
  --data "{
      \"numberOfDaysRetention\": 0,
      \"numberOfVersionsRetention\": null,
      \"oLACEnabled\": true,
      \"autoPurgeEnabled\": true,
      \"managingCPM\": \"\",
      \"safeName\": \"$1\",
      \"description\": \"poc safe\",
      \"location\": \"\"
  }"
}

add_safe_member() {
  # $1 safe_name, $2 member_name
  echo
  echo "Adding Member: $2 to Safe: $1"
  curl --location "https://$isp_subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$1/Members/" \
  --header "Authorization: Bearer $identity_token" \
  --header 'Content-Type: application/json' \
 --data "{
     \"memberName\":\"$2\",
     \"searchIn\": \"Vault\",
     \"membershipExpirationDate\":null,
     \"isReadOnly\": true,
     \"permissions\": {
       \"useAccounts\":false,
       \"retrieveAccounts\": true,
       \"listAccounts\": true,
       \"addAccounts\": false,
       \"updateAccountContent\": false,
       \"updateAccountProperties\": false,
       \"initiateCPMAccountManagementOperations\": false,
       \"specifyNextAccountContent\": false,
       \"renameAccounts\": false,
       \"deleteAccounts\": false,
       \"unlockAccounts\": false,
       \"manageSafe\": false,
       \"manageSafeMembers\": false,
       \"backupSafe\": false,
       \"viewAuditLog\": false,
       \"viewSafeMembers\": true,
       \"accessWithoutConfirmation\": true,
       \"createFolders\": false,
       \"deleteFolders\": false,
       \"moveAccountsAndFolders\": false,
       \"requestsAuthorizationLevel1\": false,
       \"requestsAuthorizationLevel2\": false
     },
     \"MemberType\": \"User\"
   }"
}

create_account_ssh_user_1() {
  # $1 safe_name
  echo
  echo "Creating Account: account-ssh-user-1 in Safe: $1"

  curl --location "https://$isp_subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/" \
  --header "Authorization: Bearer $identity_token" \
  --header 'Content-Type: application/json' \
  --data "{
      \"name\": \"account-ssh-user-1\",
      \"address\": \"196.168.0.1\",
      \"userName\": \"ssh-user-1\",
      \"platformId\": \"UnixSSH\",
      \"safeName\": \"$1\",
      \"secretType\": \"key\",
      \"secret\": \"SuperSecret1!\",
      \"platformAccountProperties\": {},
      \"secretManagement\": {
        \"automaticManagementEnabled\": true,
        \"manualManagementReason\": \"\"
      },
      \"remoteMachinesAccess\": {
        \"remoteMachines\": \"\",
        \"accessRestrictedToRemoteMachines\": true
      }
    }"
}

conjur_isp_auth(){
  conjur_token=$(curl --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/authn-oidc/cyberark/conjur/authenticate" \
  --header 'Accept-Encoding: base64' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "id_token=$identity_token")
}

conjur_list_groups(){
   curl --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/resources?kind=group" \
   --header "Authorization: Token token=\"$conjur_token\""
}

wait_for_synchronizer() {
  echo
  echo "Waiting for synchronizer (*/$safe_name/delegation/consumers)"

  conjur_isp_auth
  #echo "conjur_token: $conjur_token"

  while [[ "$(conjur_list_groups | grep "/$safe_name"/delegation/consumers)" == "" ]]; do
    echo -n "."
    sleep 2
  done
}

main "$@"
