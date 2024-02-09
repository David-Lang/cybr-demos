#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail
source "$CYBR_DEMOS_PATH/demos/isp_vars.env.sh"
main() {
  set_variables
  get_role_arn "role_name"
  get_secret_store
  create_secret_strore
  create_policy "$safe_name"
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
platform_auth() {
  # $1 client_id, $2 client_secret
  printf "\nISP Auth client_id: $1\n"
  identity_token=$(curl --location "https://$isp_id.id.cyberark.cloud/oauth2/platformtoken" \
  --header 'X-IDAP-NATIVE-CLIENT: true' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_id=$1" \
  --data-urlencode "client_secret=$2" | jq -r .access_token)
  echo "identity_token: $identity_token"
}

get_role_arn() {
  # $1 safe_name
  printf "get_role_arn: $1\n"
}

create_secret_store() {
   # $1 safe_name
   printf "create_secret_store \n"

   curl --location "https://$isp_subdomain.secretshub.cyberark.cloud/api/secret-stores" \
   --header "Authorization: Bearer $identity_token" \
   --header 'Content-Type: application/json' \
   --data "{
     \"type\": \"AWS_ASM\",
     \"description\": \"POC AWS Target\",
     \"name\": \"$1\",
     \"data\": {
               \"accountAlias\": \"$1\",
               \"accountId\": \"$2\",
               \"regionId\": \"$3\",
               \"roleName\": \"$4\"
             }
   }"

}

create_policy() {
  # $1 safe_name
  printf "create_policy: $1\n"

  curl --location "https://$isp_subdomain.secretshub.cyberark.cloud/api/policies" \
   --header "Authorization: Bearer $identity_token" \
  --header 'Content-Type: application/json' \
  --data "{
    \"name\": \"poc-policy-1\",
    \"description\": \"poc-policy-1\",
    \"source\": {
      \"id\": \"$1\"
     },
     \"target\": {
       \"id\": \"$2\"
     },
      \"filter\": {
          \"data\": {
              \"safeName\": \"$3\"
          },
          \"type\": \"PAM_SAFE\"
      }
  }"

}

main "$@"
