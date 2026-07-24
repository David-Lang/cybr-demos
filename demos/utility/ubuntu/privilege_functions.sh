#!/bin/bash
set -euo pipefail

# ensure_platform_active activates a Privilege Cloud target platform by its
# string PlatformID (e.g. AzureApplicationKeys) if it isn't already active.
# Built-in platforms ship deactivated; an account can't be onboarded under an
# inactive platform. Idempotent. Requires admin rights on the token.
ensure_platform_active() {
  # $1 isp_subdomain, $2 identity_token, $3 platform_id (string)
  if [ $# -ne 3 ]; then
    echo "Usage: ensure_platform_active isp_subdomain identity_token platform_id" >&2
    return 1
  fi
  local subdomain="$1" token="$2" pid="$3" resp numid active
  # NOTE: the ?search= filter matches the display name, not the PlatformID, so
  # list all target platforms and filter by PlatformID in jq.
  resp=$(curl --silent --location \
    "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Platforms/Targets" \
    --header "Authorization: Bearer $token" --header "Accept: application/json")
  numid=$(printf '%s' "$resp" | jq -r --arg pid "$pid" 'first(.Platforms[]? | select(.PlatformID==$pid) | .ID) // empty' 2>/dev/null)
  active=$(printf '%s' "$resp" | jq -r --arg pid "$pid" 'first(.Platforms[]? | select(.PlatformID==$pid) | .Active) // empty' 2>/dev/null)
  if [ -z "$numid" ] || [ "$numid" = "null" ]; then
    printf "\nWARN: platform '%s' not found; skipping activation.\n" "$pid" >&2
    return 0
  fi
  if [ "$active" = "true" ]; then
    printf "Platform '%s' already active.\n" "$pid" >&2
    return 0
  fi
  printf "Activating platform '%s' (target id %s)...\n" "$pid" "$numid" >&2
  curl --silent --show-error --location --request POST \
    "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Platforms/Targets/$numid/activate" \
    --header "Authorization: Bearer $token" >/dev/null
  printf "Platform '%s' activated.\n" "$pid" >&2
}

 create_safe() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, [$4 description]
   local description="${4:-poc safe}"
   printf "\nCreating Safe: $3\n"

   curl --silent --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes" \
   --header "Authorization: Bearer $2" \
   --header 'Content-Type: application/json' \
   --data "$(jq -n --arg name "$3" --arg desc "$description" '{
       numberOfDaysRetention: 0,
       numberOfVersionsRetention: null,
       oLACEnabled: true,
       autoPurgeEnabled: true,
       managingCPM: "",
       safeName: $name,
       description: $desc,
       location: ""
   }')"
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

 add_safe_secretshub_member() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 member_name
   # Grants the exact permissions Secrets Hub needs to sync a safe (per docs:
   # "Create a secret in PAM"): Retrieve + List accounts, Add account, Update
   # account properties, View Safe members, Access Safe without confirmation.
   printf "\nAdding Secrets Hub Member: $4 to Safe: $3\n"
   curl --silent --location "https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$3/Members/" \
   --header "Authorization: Bearer $2" \
   --header 'Content-Type: application/json' \
   --data "{
      \"memberName\":\"$4\",
      \"searchIn\": \"Vault\",
      \"membershipExpirationDate\":null,
      \"permissions\": {
        \"useAccounts\": false,
        \"retrieveAccounts\": true,
        \"listAccounts\": true,
        \"addAccounts\": true,
        \"updateAccountContent\": false,
        \"updateAccountProperties\": true,
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

 account_id_by_name() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 account_name
   # Echoes the account id whose .name matches account_name (fallback: first
   # account in the safe). Empty output when the safe has no accounts. Used by
   # both delete_account_by_name and the idempotent create path.
   if [ $# -ne 4 ]; then
     echo "Usage: account_id_by_name isp_subdomain identity_token safe_name account_name" >&2
     return 1
   fi
   local subdomain="$1" token="$2" safe="$3" name="$4" safe_enc resp
   # URL-encode the safe name for the OData filter (safe names can contain
   # characters that are unsafe in a query string).
   safe_enc=$(printf '%s' "$safe" | jq -sRr @uri)
   resp=$(curl --silent --location \
     "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts?filter=safeName%20eq%20$safe_enc" \
     --header "Authorization: Bearer $token" --header "Accept: application/json")
   printf '%s' "$resp" | jq -r --arg name "$name" \
     'first(.value[]? | select(.name==$name) | .id) // (.value[0].id // empty)' 2>/dev/null
 }

 create_postgres_account() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 account_name,
   # $5 username, $6 password, $7 address, $8 platform_id, [$9 port], [${10} database]
   #
   # Onboards a password credential the read path (Summon -> Conjur) resolves via
   # data/vault/<safe>/<account>/{username,password}. Automatic secrets
   # management is ENABLED so the CPM/SRS can rotate the credential (the workshop
   # queues a rotation). Port/Database are added to platformAccountProperties only
   # when provided. The JSON is jq-built to avoid shell-quoting pitfalls.
   if [ $# -lt 8 ]; then
     echo "Usage: create_postgres_account isp_subdomain identity_token safe_name account_name username password address platform_id [port] [database]" >&2
     return 1
   fi
   local subdomain="$1" token="$2" safe="$3" name="$4" username="$5" \
     password="$6" address="$7" platform_id="$8" port="${9:-}" database="${10:-}" payload
   payload=$(jq -n \
     --arg name "$name" \
     --arg address "$address" \
     --arg userName "$username" \
     --arg platformId "$platform_id" \
     --arg secret "$password" \
     --arg safeName "$safe" \
     --arg port "$port" \
     --arg database "$database" \
     '{
        name: $name,
        address: $address,
        userName: $userName,
        platformId: $platformId,
        secretType: "password",
        secret: $secret,
        safeName: $safeName,
        secretManagement: {
          automaticManagementEnabled: true
        },
        platformAccountProperties: (
          {}
          + (if ($port | length) > 0 then { Port: $port } else {} end)
          + (if ($database | length) > 0 then { Database: $database } else {} end)
        )
      }')
   printf "\nCreating Account: %s in Safe: %s\n" "$name" "$safe"
   curl --silent --location "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/" \
     --header "Authorization: Bearer $token" \
     --header 'Content-Type: application/json' \
     --data "$payload"
 }

 delete_account_by_name() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 account_name
   # Deletes the account matching account_name in safe_name (fallback: first
   # account). No-op (return 0) when the safe has no matching account.
   if [ $# -ne 4 ]; then
     echo "Usage: delete_account_by_name isp_subdomain identity_token safe_name account_name" >&2
     return 1
   fi
   local subdomain="$1" token="$2" safe="$3" name="$4" id
   id=$(account_id_by_name "$subdomain" "$token" "$safe" "$name")
   if [ -z "$id" ] || [ "$id" = "null" ]; then
     printf "\nNo account named '%s' found in Safe '%s'; nothing to delete.\n" "$name" "$safe"
     return 0
   fi
   printf "\nDeleting Account: %s (id %s) in Safe: %s\n" "$name" "$id" "$safe"
   curl --silent --request DELETE \
     --location "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/$id" \
     --header "Authorization: Bearer $token"
 }

 queue_account_rotation() {
   # $1 isp_subdomain, $2 identity_token, $3 safe_name, $4 account_name
   # Queues an immediate CPM change (rotation) of the account's credential.
   # Requires the account to have automatic secrets management enabled and a
   # CPM/connector able to reach the target. Returns non-zero if the account
   # can't be found; the change call itself is best-effort (CPM runs async).
   if [ $# -ne 4 ]; then
     echo "Usage: queue_account_rotation isp_subdomain identity_token safe_name account_name" >&2
     return 1
   fi
   local subdomain="$1" token="$2" safe="$3" name="$4" id
   id=$(account_id_by_name "$subdomain" "$token" "$safe" "$name")
   if [ -z "$id" ] || [ "$id" = "null" ]; then
     printf "\nNo account named '%s' found in Safe '%s'; cannot queue rotation.\n" "$name" "$safe" >&2
     return 1
   fi
   printf "\nQueuing CPM rotation for Account: %s (id %s) in Safe: %s\n" "$name" "$id" "$safe"
   curl --silent --request POST \
     --location "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/$id/Change/" \
     --header "Authorization: Bearer $token" \
     --header 'Content-Type: application/json' \
     --data '{"ChangeEntireGroup": false}'
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

add_ip_to_privilege_cloud_allowlist() {
  # $1 isp_subdomain, $2 identity_token
  local subdomain=$1
  local token=$2

  ip=$(curl --silent "https://checkip.amazonaws.com/")

  # Fetch the current allowlist
  response=$(curl --silent \
    --request GET \
    --location "https://$subdomain.privilegecloud.cyberark.cloud/api/advanced-settings/ip-allowlist" \
    --header "Authorization: Bearer $token" \
    --header "Accept: application/json")

  # Use jq to check if the target_ip exists in the customerPublicIPs array
  # The -e flag sets the exit status based on the result
  if echo "$response" | jq -e ".customerPublicIPs | contains([\"$ip\"])" > /dev/null; then
    printf "Result: $ip is already allowed.\n"
  else
    ip_cidr="${ip}/32"

    updated_ips=$(echo "$response" | jq -c --arg ip "$ip_cidr" '.customerPublicIPs += [$ip] | .customerPublicIPs')

    printf "Adding: $ip_cidr to the allowlist.\n"
    update_ip_allowlist "$subdomain" "$token" "$updated_ips"
    printf "\nWaiting 10 minutes for Privilege Cloud Allow List update to complete...\n"
    sleep 600
  fi
}

get_platforms() {
  # $1 isp_subdomain, $2 identity_token, [$3 search]
  local url="https://$1.privilegecloud.cyberark.cloud/PasswordVault/API/Platforms"
  if [ -n "${3:-}" ]; then
    url="${url}?search=$3"
  fi
  curl --silent --location "$url" \
    --header "Authorization: Bearer $2" \
    --header "Accept: application/json"
}

postgres_platform_available() {
  # $1 isp_subdomain, $2 identity_token, [$3 keyword; default "postgre"]
  # Returns 0 if an active platform whose id/name/systemType contains the keyword
  # exists on the tenant, else 1. Used to validate the tenant can onboard/rotate
  # the demo Postgres credential.
  local keyword="${3:-postgre}"
  local response
  response="$(get_platforms "$1" "$2")" || return 1
  printf '%s' "$response" | jq -e --arg kw "$keyword" '
      (.Platforms // [])
      | map(select(
          ((.general.active // true) == true)
          and (((.general.id // "") + " " + (.general.name // "") + " " + (.general.systemType // "")) | ascii_downcase | contains($kw | ascii_downcase))
        ))
      | length > 0
    ' >/dev/null 2>&1
}
