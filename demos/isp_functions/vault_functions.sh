#!/bin/bash

 create_safe() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name,
   printf "Creating Safe: $3\n"

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

 add_safe_admin_role() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 member_name
   printf "Adding Member: $4 to Safe: $3\n"
   curl --silent --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$3/Members/" \
   --header "Authorization: Bearer $2" \
   --header 'Content-Type: application/json' \
   --data "{
      \"memberName\":\"$3\",
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
   printf "Adding Member: $4 to Safe: $3\n"
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
   printf "Creating Account: account-ssh-user-1 in Safe: $3\n"

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
