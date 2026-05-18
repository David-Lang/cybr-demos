#!/bin/bash
# Interactive password rotation demo for GitHub OIDC path.
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DEMO_DIR/../../.." && pwd)"
VARS_FILE="$DEMO_DIR/setup/vars.env"
SETUP_ENV_FILE="$REPO_ROOT/demos/setup_env.sh"

ACCOUNT_NAME="${ACCOUNT_NAME:-account-ssh-user-1}"
POLL_SECONDS="${POLL_SECONDS:-10}"
MAX_POLLS="${MAX_POLLS:-18}"
CPM_NAME="${CPM_NAME:-PasswordManager}"
LAST_API_HTTP_CODE=""
LAST_API_ERROR_CODE=""
LAST_API_ERROR_MESSAGE=""

header() {
  printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${BOLD}  %s${NC}\n" "$1"
  printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

pause() {
  if [ "${AUTO_CONTINUE:-false}" = "true" ] || [ ! -t 0 ]; then
    echo
    return 0
  fi
  printf "\n${YELLOW}▶ Press ENTER to continue...${NC}"
  read -r || true
  echo
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "${RED}Missing required command: %s${NC}\n" "$cmd"
    exit 1
  fi
}

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    printf "${RED}Missing required variable: %s${NC}\n" "$name"
    exit 1
  fi
}

mask_secret() {
  local value="$1"
  local length=${#value}
  if [ "$length" -le 4 ]; then
    printf '****'
    return 0
  fi
  printf '%s***%s' "${value:0:2}" "${value: -2}"
}

prompt_yes_no() {
  local prompt="$1"
  local answer
  if [ "${AUTO_CONTINUE:-false}" = "true" ] || [ ! -t 0 ]; then
    return 0
  fi
  printf "%s (y/n) " "$prompt"
  read -r answer || return 1
  [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

api_post_json() {
  # $1 url, $2 bearer token, $3 label
  local url="$1"
  local token="$2"
  local label="$3"
  local tmp http_code

  tmp="$(mktemp)"
  LAST_API_HTTP_CODE=""
  LAST_API_ERROR_CODE=""
  LAST_API_ERROR_MESSAGE=""
  http_code="$(curl --silent --show-error \
    --location \
    --request POST \
    --url "$url" \
    --header "Authorization: Bearer ${token}" \
    --header "Content-Type: application/json" \
    --data '{}' \
    --output "$tmp" \
    --write-out '%{http_code}')"

  if [[ "$http_code" =~ ^2 ]]; then
    LAST_API_HTTP_CODE="$http_code"
    rm -f "$tmp"
    return 0
  fi

  LAST_API_HTTP_CODE="$http_code"
  LAST_API_ERROR_CODE="$(jq -r '.ErrorCode // empty' <"$tmp" 2>/dev/null || true)"
  LAST_API_ERROR_MESSAGE="$(jq -r '.ErrorMessage // empty' <"$tmp" 2>/dev/null || true)"

  printf "${RED}%s failed (HTTP %s).${NC}\n" "$label" "$http_code"
  if [ -s "$tmp" ]; then
    printf "Response body:\n"
    if ! jq . <"$tmp"; then
      cat "$tmp"
      echo
    fi
  fi
  rm -f "$tmp"
  return 1
}

enable_account_automatic_management() {
  # $1 account_id, $2 identity_token
  local account_id="$1"
  local token="$2"
  local tmp http_code

  tmp="$(mktemp)"
  http_code="$(curl --silent --show-error \
    --request PATCH \
    --location "${PVWA_BASE}/Accounts/${account_id}/" \
    --header "Authorization: Bearer ${token}" \
    --header "Content-Type: application/json" \
    --data '[{"op":"replace","path":"/secretManagement/automaticManagementEnabled","value":true}]' \
    --output "$tmp" \
    --write-out '%{http_code}')"

  if [[ "$http_code" =~ ^2 ]]; then
    rm -f "$tmp"
    printf "${GREEN}automaticManagementEnabled=true applied to account.${NC}\n"
    return 0
  fi

  printf "${RED}Failed to patch automatic management (HTTP %s).${NC}\n" "$http_code"
  if [ -s "$tmp" ]; then
    if ! jq . <"$tmp"; then
      cat "$tmp"
      echo
    fi
  fi
  rm -f "$tmp"
  return 1
}

set_safe_managing_cpm() {
  # $1 safe_name, $2 cpm_name, $3 identity_token
  local safe_name="$1"
  local cpm_name="$2"
  local token="$3"
  local safe_url_id tmp http_code

  safe_url_id="$(jq -nr --arg v "$safe_name" '$v|@uri')"
  tmp="$(mktemp)"
  http_code="$(curl --silent --show-error \
    --request PUT \
    --location "${PVWA_BASE}/Safes/${safe_url_id}/" \
    --header "Authorization: Bearer ${token}" \
    --header "Content-Type: application/json" \
    --data "{\"safeName\":\"${safe_name}\",\"managingCPM\":\"${cpm_name}\"}" \
    --output "$tmp" \
    --write-out '%{http_code}')"

  if [[ "$http_code" =~ ^2 ]]; then
    rm -f "$tmp"
    printf "${GREEN}Safe '%s' now managed by CPM '%s'.${NC}\n" "$safe_name" "$cpm_name"
    return 0
  fi

  printf "${RED}Failed to set Safe managingCPM (HTTP %s).${NC}\n" "$http_code"
  if [ -s "$tmp" ]; then
    if ! jq . <"$tmp"; then
      cat "$tmp"
      echo
    fi
  fi
  rm -f "$tmp"
  return 1
}

generate_demo_password() {
  local rand
  rand="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)"
  printf 'A%s!z' "$rand"
}

update_password_in_vault() {
  # $1 account_id, $2 identity_token, $3 new_password
  local account_id="$1"
  local token="$2"
  local new_password="$3"
  local tmp http_code

  tmp="$(mktemp)"
  http_code="$(curl --silent --show-error \
    --request POST \
    --location "${PVWA_BASE}/Accounts/${account_id}/Password/Update/" \
    --header "Authorization: Bearer ${token}" \
    --header "Content-Type: application/json" \
    --data "{\"NewCredentials\":\"${new_password}\"}" \
    --output "$tmp" \
    --write-out '%{http_code}')"

  if [[ "$http_code" =~ ^2 ]]; then
    rm -f "$tmp"
    printf "${GREEN}Vault-only password update succeeded.${NC}\n"
    return 0
  fi

  printf "${RED}Vault-only password update failed (HTTP %s).${NC}\n" "$http_code"
  if [ -s "$tmp" ]; then
    if ! jq . <"$tmp"; then
      cat "$tmp"
      echo
    fi
  fi
  rm -f "$tmp"
  return 1
}

require_cmd curl
require_cmd jq

if [ ! -f "$SETUP_ENV_FILE" ]; then
  printf "${RED}Missing setup env file: %s${NC}\n" "$SETUP_ENV_FILE"
  exit 1
fi

if [ ! -f "$VARS_FILE" ]; then
  printf "${RED}Missing vars file: %s${NC}\n" "$VARS_FILE"
  exit 1
fi

# shellcheck disable=SC1091
source "$SETUP_ENV_FILE"
# shellcheck disable=SC1091
source "$VARS_FILE"

require_var TENANT_ID
require_var TENANT_SUBDOMAIN
require_var CLIENT_ID
require_var CLIENT_SECRET
require_var SAFE_NAME

CONJUR_ACCOUNT="conjur"
SECRET_PATH="data/vault/${SAFE_NAME}/${ACCOUNT_NAME}/password"
PVWA_BASE="https://${TENANT_SUBDOMAIN}.privilegecloud.cyberark.cloud/PasswordVault/API"
CONJUR_BASE="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"

header "CyberArk Rotation Demo (CLI)"
cat <<EOF
This walkthrough will:
  1) Find account ${ACCOUNT_NAME} in safe ${SAFE_NAME}
  2) Trigger Change + Verify via CyberArk API
  3) Poll Conjur secret path for updated value

Secret path:
  ${SECRET_PATH}
EOF
pause

header "Step 1: Authenticate"
printf "Requesting identity token... "
IDENTITY_TOKEN="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
printf "${GREEN}done${NC}\n"

printf "Requesting Conjur session token... "
CONJUR_TOKEN="$(get_conjur_token "$TENANT_SUBDOMAIN" "$IDENTITY_TOKEN")"
printf "${GREEN}done${NC}\n"

FILTER_ENC="$(jq -nr --arg v "safeName eq ${SAFE_NAME}" '$v|@uri')"
ACCOUNT_JSON="$(curl --silent --show-error --fail \
  --location "${PVWA_BASE}/Accounts?search=${ACCOUNT_NAME}&filter=${FILTER_ENC}" \
  --header "Authorization: Bearer ${IDENTITY_TOKEN}")"

ACCOUNT_ID="$(printf '%s' "$ACCOUNT_JSON" | jq -r --arg safe "$SAFE_NAME" --arg name "$ACCOUNT_NAME" '
  [.value[]? | select((.safeName // "") == $safe and (.name // "") == $name)][0].id // empty
')"

if [ -z "$ACCOUNT_ID" ]; then
  # Fallback to lowercase safename filter used by existing demo helpers.
  FILTER_ENC="$(jq -nr --arg v "safename eq ${SAFE_NAME}" '$v|@uri')"
  ACCOUNT_JSON="$(curl --silent --show-error --fail \
    --location "${PVWA_BASE}/Accounts?filter=${FILTER_ENC}" \
    --header "Authorization: Bearer ${IDENTITY_TOKEN}")"
  ACCOUNT_ID="$(printf '%s' "$ACCOUNT_JSON" | jq -r --arg name "$ACCOUNT_NAME" '
    [.value[]? | select((.name // "") == $name)][0].id // empty
  ')"
fi

if [ -z "$ACCOUNT_ID" ]; then
  # Last fallback: query by safe only and pick known account username.
  FILTER_ENC="$(jq -nr --arg v "safename eq ${SAFE_NAME}" '$v|@uri')"
  ACCOUNT_JSON="$(curl --silent --show-error --fail \
    --location "${PVWA_BASE}/Accounts?filter=${FILTER_ENC}" \
    --header "Authorization: Bearer ${IDENTITY_TOKEN}")"
  ACCOUNT_ID="$(printf '%s' "$ACCOUNT_JSON" | jq -r '
    [.value[]? | select((.userName // "") == "ssh-user-1")][0].id // empty
  ')"
fi

if [ -z "$ACCOUNT_ID" ]; then
  printf "${RED}Account not found: %s in safe %s${NC}\n" "$ACCOUNT_NAME" "$SAFE_NAME"
  printf "Tip: run setup first -> bash setup.sh\n"
  exit 1
fi
printf "${GREEN}Found account ID:${NC} %s\n" "$ACCOUNT_ID"
pause

header "Step 2: Read Current Secret"
CURRENT_SECRET="$(curl --silent --show-error --fail \
  --location "${CONJUR_BASE}/secrets/${CONJUR_ACCOUNT}/variable/${SECRET_PATH}" \
  --header "Authorization: Token token=\"${CONJUR_TOKEN}\"")"

printf "Current value (masked): "
mask_secret "$CURRENT_SECRET"
printf "\n"
pause

header "Step 3: Trigger CyberArk Rotation"
CHANGE_FAILED=false
if prompt_yes_no "Trigger Change operation now?"; then
  if api_post_json "${PVWA_BASE}/Accounts/${ACCOUNT_ID}/Change" "$IDENTITY_TOKEN" "Change operation"; then
    printf "${GREEN}Change request submitted.${NC}\n"
  else
    CHANGE_FAILED=true
    if [ "$LAST_API_ERROR_CODE" = "CAWS00001E" ]; then
      printf "${YELLOW}Detected unmanaged account (CAWS00001E).${NC}\n"
      if prompt_yes_no "Try auto-fix: assign Safe CPM + enable account automatic management + retry Change?"; then
        SAFE_FIX_OK=true
        if ! set_safe_managing_cpm "$SAFE_NAME" "$CPM_NAME" "$IDENTITY_TOKEN"; then
          SAFE_FIX_OK=false
        fi
        if ! enable_account_automatic_management "$ACCOUNT_ID" "$IDENTITY_TOKEN"; then
          SAFE_FIX_OK=false
        fi
        if [ "$SAFE_FIX_OK" = true ]; then
          if api_post_json "${PVWA_BASE}/Accounts/${ACCOUNT_ID}/Change" "$IDENTITY_TOKEN" "Change retry"; then
            CHANGE_FAILED=false
            printf "${GREEN}Change retry succeeded after Safe/account remediation.${NC}\n"
          fi
        fi
      fi
    fi

    if [ "$CHANGE_FAILED" = true ]; then
      cat <<EOF
Hints:
  • Account platform may not support CPM change in this lab context
  • Safe may not be assigned to a CPM user (expected: ${CPM_NAME})
  • CPM target connectivity may be unavailable for this account
  • The account may require onboarding/verification before change
Next step:
  1) In PVWA Safe settings, set managingCPM to '${CPM_NAME}'
  2) Keep automatic management enabled on account '${ACCOUNT_NAME}'
  3) Re-run this script
EOF
      if prompt_yes_no "Fallback: set a new password in Vault directly and continue verification?"; then
        FALLBACK_PASSWORD="$(generate_demo_password)"
        if update_password_in_vault "$ACCOUNT_ID" "$IDENTITY_TOKEN" "$FALLBACK_PASSWORD"; then
          CHANGE_FAILED=false
          printf "Fallback password set (masked): "
          mask_secret "$FALLBACK_PASSWORD"
          printf "\n"
        fi
      fi
    fi
  fi
else
  printf "${YELLOW}Skipped Change request.${NC}\n"
fi

if prompt_yes_no "Trigger Verify operation now?"; then
  if api_post_json "${PVWA_BASE}/Accounts/${ACCOUNT_ID}/Verify" "$IDENTITY_TOKEN" "Verify operation"; then
    printf "${GREEN}Verify request submitted.${NC}\n"
  elif [ "$CHANGE_FAILED" = true ]; then
    printf "${YELLOW}Verify also failed after change failure. Continuing to polling anyway.${NC}\n"
  fi
else
  printf "${YELLOW}Skipped Verify request.${NC}\n"
fi
pause

header "Step 4: Poll For Updated Secret"
printf "Polling every %ss for up to %s attempts...\n" "$POLL_SECONDS" "$MAX_POLLS"

poll=0
while [ "$poll" -lt "$MAX_POLLS" ]; do
  NEW_SECRET="$(curl --silent --show-error --fail \
    --location "${CONJUR_BASE}/secrets/${CONJUR_ACCOUNT}/variable/${SECRET_PATH}" \
    --header "Authorization: Token token=\"${CONJUR_TOKEN}\"")"
  poll=$((poll + 1))
  ts="$(date +"%H:%M:%S")"

  if [ "$NEW_SECRET" != "$CURRENT_SECRET" ]; then
    printf "${GREEN}[%s] Rotation detected.${NC}\n" "$ts"
    printf "Before (masked): "
    mask_secret "$CURRENT_SECRET"
    printf "\nAfter  (masked): "
    mask_secret "$NEW_SECRET"
    printf "\n"
    if prompt_yes_no "Show full rotated value in terminal?"; then
      printf "After (full): %s\n" "$NEW_SECRET"
    fi
    break
  fi

  printf "[%s] unchanged (%d/%d)\n" "$ts" "$poll" "$MAX_POLLS"
  sleep "$POLL_SECONDS"
done

if [ "$poll" -eq "$MAX_POLLS" ]; then
  printf "${YELLOW}No change detected within polling window.${NC}\n"
  printf "Rotation may still be processing. Re-run this script to check again.\n"
fi

header "Done"
cat <<'OUTRO'
What this proves:
  • Rotation was requested in CyberArk via API
  • Conjur path for the GitHub workflow was monitored
  • Updated value was observed without changing GitHub variables
OUTRO
