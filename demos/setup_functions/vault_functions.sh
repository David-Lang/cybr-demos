#!/bin/bash
set -euo pipefail

 create_safe() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name,
   printf "\nCreating Safe: $3\n"

   curl --silent --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes" \
   --header "Authorization: Bearer $2" \
   --header 'Content-Type: application/json' \
   --data "{
       \"numberOfDaysRetention\": 0,
       \"numberOfVersionsRetention\": null,
       \"oLACEnabled\": true,
       \"autoPurgeEnabled\": true,
       \"managingCPM\": \"\",
       \"safeName\": \"$3\",
       \"description\": \"poc safe\",
       \"location\": \"\"
   }"
 }

  delete_safe() {
    # $1 isp_subdomain, $2 identity_token, $3 safe_name,
    printf "\nDeleting Safe: $3\n"
    safeUrlId="$3"

    curl --silent \
    --request DELETE \
    --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$safeUrlId" \
    --header "Authorization: Bearer $2"
  }

 add_safe_admin_role() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 member_name
   printf "\nAdding Member: \"$4\" to Safe: \"$3\"\n"
   curl --silent --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$3/Members/" \
   --header "Authorization: Bearer $2" \
   --header 'Content-Type: application/json' \
   --data "{
      \"memberName\":\"$4\",
      \"searchIn\": \"Vault\",
      \"membershipExpirationDate\":null,
      \"isReadOnly\": true,
      \"permissions\": {
        \"useAccounts\":true,
        \"retrieveAccounts\": true,
        \"listAccounts\": true,
        \"addAccounts\": true,
        \"updateAccountContent\": true,
        \"updateAccountProperties\": true,
        \"initiateCPMAccountManagementOperations\": true,
        \"specifyNextAccountContent\": true,
        \"renameAccounts\": true,
        \"deleteAccounts\": true,
        \"unlockAccounts\": true,
        \"manageSafe\": true,
        \"manageSafeMembers\": true,
        \"backupSafe\": true,
        \"viewAuditLog\": true,
        \"viewSafeMembers\": true,
        \"accessWithoutConfirmation\": true,
        \"createFolders\": true,
        \"deleteFolders\": true,
        \"moveAccountsAndFolders\": true,
        \"requestsAuthorizationLevel1\": false,
        \"requestsAuthorizationLevel2\": false
      },
      \"MemberType\": \"Role\"
    }"
 }

 add_safe_read_member() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 member_name
   printf "\nAdding Member: $4 to Safe: $3\n"
   curl --silent --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$3/Members/" \
   --header "Authorization: Bearer $2" \
   --header 'Content-Type: application/json' \
   --data "{
      \"memberName\":\"$4\",
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
   # $1 isp_subdomain, $2 identity_token, $3 safe_name
   printf "\nCreating Account: account-ssh-user-1 in Safe: $3\n"

   curl --silent --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/" \
   --header "Authorization: Bearer $2" \
   --header 'Content-Type: application/json' \
   --data "{
       \"name\": \"account-ssh-user-1\",
       \"address\": \"196.168.0.1\",
       \"userName\": \"ssh-user-1\",
       \"platformId\": \"UnixSSH\",
       \"safeName\": \"$3\",
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


 delete_account_ssh_user_1() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name
   printf "\nDeleting Account: account-ssh-user-1 in Safe: $3\n"

   id=$(curl --silent \
   --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts?filter=safename%20eq%20$3" \
   --header "Authorization: Bearer $2" | jq -r .value[0].id)

   printf "\nDeleting Account Id: account-ssh-user-1 in Safe: $3 Id: $id\n"
   curl --silent \
   --request DELETE \
   --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/$id" \
   --header "Authorization: Bearer $2" \

 }

 # Can take 10 mins to be applied, no additional updates can happen will being applied
 update_ip_allowlist() {
   # $1 isp_subdomain, $2 identity_token, $3 json_array_of_ips ('["1.0.0.4/32","2.0.0.5/24"]')
   printf "\nUpdating Privilege Cloud IP Allowlist: $3\n"
   ipListJson="$3"

   curl --silent \
     --request PUT \
     --location "https://$1.privilegecloud.cyberark.cloud/api/advanced-settings/ip-allowlist" \
     --header "Authorization: Bearer $2" \
     --header "Content-Type: application/json" \
     --data "{ \"customerPublicIPs\": $ipListJson }"
 }

create_app() {
  # $1 isp_subdomain, $2 identity_token, $3 app_id

  if [ $# -ne 3 ]; then
    printf "\nUsage: create_application <isp_subdomain> <identity_token> <app_id>\n"
    return 1
  fi

  printf "\nCreating Application: %s\n" "$3"

  curl --silent \
    --request POST \
    --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/WebServices/PIMServices.svc/Applications/" \
    --header "Authorization: Bearer $2" \
    --header "Content-Type: application/json" \
    --data "{
      \"application\": {
        \"AppID\": \"$3\"
      }
    }"
}

add_app_authentication() {
  # $1 isp_subdomain, $2 identity_token, $3 app_id, $4 auth_type, $5 auth_value

  # Allowed Authentication Types (auth_type values):
  #
  #   machineAddress      – IP or CIDR of allowed machine (e.g. 203.0.113.0/24)
  #   osUser              – OS user allowed to authenticate (e.g. ec2-user)
  #   path                – Application path (e.g. /usr/local/bin/myapp)
  #   hash                – File hash authentication (SHA-1)
  #   certificate         – Application certificate (Base64)
  #   domain              – Domain name authentication
  #   group               – AD group authentication

  if [ $# -ne 5 ]; then
    printf "\nUsage: add_app_authentication <isp_subdomain> <identity_token> <app_id> <auth_type> <auth_value>\n"
    return 1
  fi

  printf "\nAdding %s auth to Application: %s (%s)\n" "$4" "$3" "$5"

  curl --silent \
    --request POST \
    --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/WebServices/PIMServices.svc/Applications/$3/Authentications/" \
    --header "Authorization: Bearer $2" \
    --header "Content-Type: application/json" \
    --data "{
      \"authentication\": {
        \"AuthType\": \"$4\",
        \"AuthValue\": \"$5\"
      }
    }"
}

add_app_certificate_attr_auth() {
  # $1 isp_subdomain
  # $2 identity_token
  # $3 app_id
  # $4 issuer_json_array                 e.g. '["CN=Thawte RSA CA 2018","OU=www.digicert.com"]'
  # $5 subject_json_array                e.g. '["CN=yourcompany.com","OU=IT","C=IL"]'
  # $6 san_json_array                    e.g. '["DNS Name=www.example.com","IP Address=1.2.3.4"]'

  if [ $# -ne 6 ]; then
    printf "\nUsage: add_app_certificateattr_auth <isp_subdomain> <identity_token> <app_id> <issuer_json_array> <subject_json_array> <san_json_array>\n"
    printf "  Example issuer_json_array : '[\"CN=Thawte RSA CA 2018\",\"OU=www.digicert.com\"]'\n"
    printf "  Example subject_json_array: '[\"CN=yourcompany.com\",\"OU=IT\",\"C=IL\"]'\n"
    printf "  Example san_json_array    : '[\"DNS Name=www.example.com\",\"IP Address=1.2.3.4\"]'\n"
    return 1
  fi

  printf "\nAdding certificateattr auth to Application: %s\n" "$3"

  curl --silent \
    --request POST \
    --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/WebServices/PIMServices.svc/Applications/$3/Authentications/" \
    --header "Authorization: Bearer $2" \
    --header "Content-Type: application/json" \
    --data "{
      \"authentication\": {
        \"AuthType\": \"certificateattr\",
        \"Issuer\": $4,
        \"Subject\": $5,
        \"SubjectAlternativeName\": $6
      }
    }"
}

