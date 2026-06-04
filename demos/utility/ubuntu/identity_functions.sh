#!/bin/bash
set -euo pipefail

get_identity_token() {
  # $1 isp_id, $2 client_id, $3 client_secret
  if [ $# -ne 3 ]; then
      echo "Usage: get_identity_token <isp_id> <client_id> <client_secret>" >&2
      return 1
  fi

  local tmp resp http_code access_token last_http
  local -a paths
  local path i npath attempt_lines
  # Build path list without ever expanding an empty `paths[@]` under `set -u` (Bash 5.x).
  # Optional override is tried first; we always include the two standard paths (deduped).
  if [[ -n "${CYBERARK_IDENTITY_TOKEN_PATH:-}" ]] \
    && [[ "${CYBERARK_IDENTITY_TOKEN_PATH}" != "/oauth2/platformtoken" ]] \
    && [[ "${CYBERARK_IDENTITY_TOKEN_PATH}" != "/api/idadmin/oauth2/platformtoken" ]]; then
    paths=(
      "${CYBERARK_IDENTITY_TOKEN_PATH}"
      /oauth2/platformtoken
      /api/idadmin/oauth2/platformtoken
    )
  else
    paths=(/oauth2/platformtoken /api/idadmin/oauth2/platformtoken)
  fi

  tmp=$(mktemp) || {
    printf 'ERROR: mktemp failed\n' >&2
    return 1
  }

  npath=${#paths[@]}
  if ((npath < 1)); then
    printf 'ERROR: no token URL paths to try (internal bug).\n' >&2
    exit 1
  fi
  attempt_lines=""
  local -a diag_bodies
  for ((i = 0; i < npath; i++)); do
    path="${paths[i]}"
    http_code=$(curl --silent --show-error --location "https://$1.id.cyberark.cloud${path}" \
      --header 'X-IDAP-NATIVE-CLIENT: true' \
      --header 'Content-Type: application/x-www-form-urlencoded' \
      --header 'Accept: application/json' \
      --data-urlencode 'grant_type=client_credentials' \
      --data-urlencode "client_id=$2" \
      --data-urlencode "client_secret=$3" \
      -o "$tmp" -w '%{http_code}')
    resp=$(cat "$tmp")
    last_http=$http_code
    attempt_lines+=$(printf '\n  %s -> HTTP %s, %s bytes' "${path}" "${http_code}" "${#resp}")
    if [[ -n "${resp//[$'\t\r\n ']/}" ]]; then
      diag_bodies+=("$resp")
    fi

    access_token=$(printf '%s' "$resp" | jq -r '
      ((.access_token // .Result.access_token // .result.access_token) // empty)
      | if . == null then empty else . end
      | if type == "string" then . else empty end
    ')

    if [[ -n "$access_token" && "$access_token" != "null" && "$access_token" == *.*.* ]]; then
      rm -f "$tmp"
      printf '%s' "$access_token"
      return 0
    fi
  done

  # OAuth2 /oauth2/token/<Application ID> with client credentials in POST body (same style as platformtoken).
  if [[ -n "${CYBERARK_OAUTH_APP_ID:-}" ]]; then
    path="/oauth2/token/${CYBERARK_OAUTH_APP_ID}"
    http_code=$(curl --silent --show-error --location "https://$1.id.cyberark.cloud${path}" \
      --header 'X-IDAP-NATIVE-CLIENT: true' \
      --header 'Content-Type: application/x-www-form-urlencoded' \
      --header 'Accept: application/json' \
      --data-urlencode 'grant_type=client_credentials' \
      --data-urlencode "client_id=$2" \
      --data-urlencode "client_secret=$3" \
      -o "$tmp" -w '%{http_code}')
    resp=$(cat "$tmp")
    last_http=$http_code
    attempt_lines+=$(printf '\n  %s (form) -> HTTP %s, %s bytes' "${path}" "${http_code}" "${#resp}")
    if [[ -n "${resp//[$'\t\r\n ']/}" ]]; then
      diag_bodies+=("$resp")
    fi
    access_token=$(printf '%s' "$resp" | jq -r '
      ((.access_token // .Result.access_token // .result.access_token) // empty)
      | if . == null then empty else . end
      | if type == "string" then . else empty end
    ')
    if [[ -n "$access_token" && "$access_token" != "null" && "$access_token" == *.*.* ]]; then
      rm -f "$tmp"
      printf '%s' "$access_token"
      return 0
    fi
  fi

  # Fallback: Identity "client credentials" with HTTP Basic (see Identity Administration OAuth docs).
  # Some tenants accept this when form+platformtoken is rejected or routed differently.
  local basic_auth tp
  local -a token_paths
  basic_auth=$(printf '%s:%s' "$2" "$3" | base64 | tr -d '\n')
  # Bare /oauth2/token/ often returns invalid_request / "unknown app" — Identity expects
  # /oauth2/token/<Application ID> (Settings on the OAuth2 Client / Server app in Identity Admin).
  token_paths=()
  if [[ -n "${CYBERARK_OAUTH_APP_ID:-}" ]]; then
    token_paths+=("/oauth2/token/${CYBERARK_OAUTH_APP_ID}")
  fi
  token_paths+=('/oauth2/token/')
  for tp in "${token_paths[@]}"; do
    http_code=$(curl --silent --show-error --location "https://$1.id.cyberark.cloud${tp}" \
      --header "Authorization: Basic ${basic_auth}" \
      --header 'Content-Type: application/x-www-form-urlencoded' \
      --header 'Accept: application/json' \
      --data-urlencode 'grant_type=client_credentials' \
      -o "$tmp" -w '%{http_code}')
    resp=$(cat "$tmp")
    last_http=$http_code
    attempt_lines+=$(printf '\n  %s (Basic) -> HTTP %s, %s bytes' "${tp}" "${http_code}" "${#resp}")
    if [[ -n "${resp//[$'\t\r\n ']/}" ]]; then
      diag_bodies+=("$resp")
    fi
    access_token=$(printf '%s' "$resp" | jq -r '
      ((.access_token // .Result.access_token // .result.access_token) // empty)
      | if . == null then empty else . end
      | if type == "string" then . else empty end
    ')
    if [[ -n "$access_token" && "$access_token" != "null" && "$access_token" == *.*.* ]]; then
      rm -f "$tmp"
      printf '%s' "$access_token"
      return 0
    fi
  done

  rm -f "$tmp"

  printf '\nERROR: Get Identity Token failed. No usable access_token from any configured path.\n' >&2
  printf 'ISPSS tenant (id.cyberark.cloud label): %s  (last attempt HTTP %s)\n' "$1" "${last_http:-unknown}" >&2
  printf 'Per-path results:%s\n' "$attempt_lines" >&2
  nd=${#diag_bodies[@]}
  printf 'HTTP error bodies (%d non-empty):\n' "$nd" >&2
  if ((nd < 1)); then
    printf '(none — every attempt returned an empty body. Wrong ISPSS id is common: confirm TENANT_ID matches your tenant URL in Identity admin.)\n' >&2
    printf 'Hint: set CYBERARK_IDENTITY_TOKEN_PATH only if CyberArk documents a different token path.\n' >&2
  else
    local j
    for ((j = 0; j < nd; j++)); do
      printf -- '--- body %d (%d bytes) ---\n' "$j" "${#diag_bodies[j]}" >&2
      printf -- '%s\n' "${diag_bodies[j]}" | jq . 2>/dev/null >&2 || printf -- '%s\n' "${diag_bodies[j]}" >&2
    done
  fi
  if ((nd > 0)); then
    local k unk
    unk=0
    for ((k = 0; k < nd; k++)); do
      if printf '%s' "${diag_bodies[k]}" | jq -e '.error_description | test("unknown app")' >/dev/null 2>&1; then
        unk=1
        break
      fi
    done
    if ((unk)); then
      printf '\nIf CYBERARK_OAUTH_APP_ID is set but token still fails: the path segment is usually the **Application ID** from the OAuth2 app **Settings** (often a UUID), not the internal **ServiceName** (e.g. smemcp_oauth_client). Copy Application ID from Identity Admin.\n' >&2
    fi
  fi
  printf '\nNEXT: run the K8s prerequisite script (DNS + token + Conjur + kubectl in one pass):\n' >&2
  printf '  export CYBR_DEMOS_PATH=/path/to/cybr-demos\n' >&2
  printf "  bash \"\$CYBR_DEMOS_PATH/demos/secrets_manager/k8s/check_prereqs.sh\"\n" >&2
  exit 1
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


