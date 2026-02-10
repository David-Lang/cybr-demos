#!/bin/bash
set -euo pipefail

get_identity_token() {
  # $1 isp_id, $2 client_id, $3 client_secret
  if [ $# -ne 3 ]; then
      echo "Usage: get_identity_token client_id, client_secret, isp_id"
      return 1
  fi

access_token=$(curl --silent --location "https://$1.id.cyberark.cloud/oauth2/platformtoken" \
  --header 'X-IDAP-NATIVE-CLIENT: true' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_id=$2" \
  --data-urlencode "client_secret=$3" | jq -r .access_token)

  # Check if access_token is empty or null
  if [ -z "$access_token" ] || [ "$access_token" == "null" ]; then
    printf "\nERROR: Get Identity Token failed. Access token is empty or null.\n" >&2
    exit 1
  fi

  #Return the token to the caller via stdout
  printf '%s' "$access_token"
}

get_uuid_by_userid() {
  # $1 isp_id, $2 identity_token, $3 username
  if [ $# -ne 3 ]; then
    echo "Usage: get_uuid_by_userid isp_id identity_token username" >&2
    return 1
  fi

  local isp_id="$1"
  local token="$2"
  local username="$3"

  local response
  response=$(curl --silent --location --request POST \
    "https://${isp_id}.id.cyberark.cloud/CDirectoryService/GetUserByName" \
    --header "authorization: Bearer ${token}" \
    --header "content-type: application/json" \
    --data "$(jq -cn --arg u "$username" '{username:$u}')"
  )

  if [ -z "$response" ] || [ "$response" = "null" ]; then
    printf "\nERROR: GetUserByName failed. Response is empty or null.\n" >&2
    return 1
  fi

  # Fail fast if API says it failed
  local success
  success=$(printf '%s' "$response" | jq -r '.success // false' 2>/dev/null)
  if [ "$success" != "true" ]; then
    local msg
    msg=$(printf '%s' "$response" | jq -r '.Message // .Result.Message // empty' 2>/dev/null)
    printf "\nERROR: GetUserByName failed. success=false. %s\nResponse: %s\n" "$msg" "$response" >&2
    return 1
  fi

  # Extract UUID from the right spot
  local user_uuid
  user_uuid=$(printf '%s' "$response" | jq -r '.Result.Uuid // empty' 2>/dev/null)

  if [ -z "$user_uuid" ] || [ "$user_uuid" = "null" ]; then
    printf "\nERROR: GetUserByName failed. Uuid not found.\nResponse: %s\n" "$response" >&2
    return 1
  fi

  printf '%s' "$user_uuid"
}

set_user_lock_state() {
  # $1 isp_id, $2 identity_token, $3 user_id, $4 lock_flag (true|false)
  if [ $# -ne 4 ]; then
    echo "Usage: set_cloud_lock isp_id identity_token user_email lock_flag"
    return 1
  fi

  local isp_id="$1"
  local identity_token="$2"
  local user_id="$3"
  local lock_flag="$4"

  echo "Updating lock state fo $user_id to $lock_flag"

  response=$(curl --silent --request POST \
    --location "https://${isp_id}.id.cyberark.cloud/UserMgmt/SetCloudLock?user=${user_id}&lockUser=${lock_flag}" \
    --header "authorization: Bearer ${identity_token}" \
    --header "content-type: application/json" \
    --data '{}'
  )

  # Get Installer users ID, then Un-"Disable" account
  local user_uuid=$(get_uuid_by_userid  $isp_id $identity_token $user_id)

  curl --request POST \
    --location "https://${isp_id}.id.cyberark.cloud/CDirectoryService/ChangeUserState" \
    --header 'Accept: */*' \
    --header "authorization: Bearer ${identity_token}" \
    --header 'Content-Type: application/json' \
    --data "{\"ID\": \"$user_uuid\",\"state\": \"true\"}"

  # Basic failure detection
  if [ -z "$response" ]; then
    printf "\nERROR: SetLock failed. Empty response.\n" >&2
  fi

  # Validate expected success shape: {"success":true,"Result":true,...}
  success=$(printf '%s' "$response" | jq -r '.success // empty' 2>/dev/null)
  result=$(printf '%s' "$response" | jq -r '.Result // empty' 2>/dev/null)

  if [ "$success" != "true" ] || [ "$result" != "true" ]; then
    printf "\nERROR: SetLock failed. success=%s result=%s errorCode=%s message=%s\nResponse: %s\n"
    printf '%s' "$response"
  fi

}

reset_user_password() {
  # $1 isp_id, $2 identity_token, $3 user_uuid, $4 user_secret
  if [ $# -ne 4 ]; then
    echo "Usage: reset_user_password isp_id identity_token user_uuid user_secret"
    return 1
  fi

  response=$(curl --silent --location --request POST \
    "https://$1.id.cyberark.cloud/UserMgmt/ResetUserPassword" \
    --header "authorization: Bearer $2" \
    --header "content-type: application/json" \
    --data "$(jq -cn --arg id "$3" --arg pw "$4" '{ID:$id,newPassword:$pw}')"
  )

  # Check if response is empty or null (some APIs may return empty; keep strict like your style)
  if [ -z "$response" ] || [ "$response" == "null" ]; then
    printf "\nERROR: ResetUserPassword failed. Response is empty or null.\n" >&2
    exit 1
  fi

  # If API returns a success flag, enforce it (safe even if it doesn't exist)
  success=$(printf '%s' "$response" | jq -r '.success // empty' 2>/dev/null)
  if [ -n "$success" ] && [ "$success" != "true" ]; then
    message=$(printf '%s' "$response" | jq -r '.Message // .message // empty' 2>/dev/null)
    errorCode=$(printf '%s' "$response" | jq -r '.ErrorCode // .errorCode // empty' 2>/dev/null)
    errorID=$(printf '%s' "$response" | jq -r '.ErrorID // .errorID // empty' 2>/dev/null)

    printf "\nERROR: ResetUserPassword returned success=false. Message=%s ErrorCode=%s ErrorID=%s\nResponse: %s\n" \
      "$message" "$errorCode" "$errorID" "$response" >&2
    exit 1
  fi

  # Optional: echo response for debugging
  # printf '%s\n' "$response"
}


