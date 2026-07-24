#!/bin/bash
# shellcheck disable=SC2059
#
# teardown.sh — "Onboard Azure AKV" activity teardown.
#
# Removes the Idira/CyberArk side of a Secret Store that setup.sh onboarded:
#   1. Delete the Secrets Hub sync policy(ies) targeting the AKV store.
#   2. Delete the AKV secret store (Secrets Hub).
#   3. Delete the Privilege Cloud account(s) in the App Safe, then the Safe.
#
# The Azure side (the Key Vault + rotation-demo app registration) is torn down
# separately by the app before this runs. This script is idempotent and
# warn-and-continue: missing objects are fine, so a partially-onboarded store
# still tears down cleanly. Prints __TEARDOWN_AKV_OK__ on completion.
#
# Inputs come from the environment (the app's teardown Job injects them):
#   LAB_ID TENANT_ID TENANT_SUBDOMAIN CLIENT_ID CLIENT_SECRET
#   SAFE_NAME AKV_VAULT_NAME AKV_VAULT_URL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OK_SENTINEL="__TEARDOWN_AKV_OK__"

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  printf "ERROR: CYBR_DEMOS_PATH is not set. Export it with the path to the cybr-demos repo.\n" >&2
  exit 1
fi

# Loads + validates tenant vars and sources the shared utility functions.
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

# Activity-local Secrets Hub / teardown helpers.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

require_input() {
  local name="$1" value="${!1:-}"
  if [ -z "$value" ]; then
    printf "ERROR: required input %s is not set (inject it via the Job env).\n" "$name" >&2
    exit 1
  fi
}

require_input SAFE_NAME
require_input AKV_VAULT_URL

SECRETSHUB_ADMIN_ROLE="${SECRETSHUB_ADMIN_ROLE:-Secrets Manager - Secrets Hub Admin}"

main() {
  local subdomain="$TENANT_SUBDOMAIN"
  printf "\n== Teardown Azure AKV (%s) — lab %s, tenant %s ==\n" "${AKV_VAULT_NAME:-?}" "${LAB_ID:-?}" "$subdomain"

  printf "\n[1/4] Authenticating to CyberArk ISPSS...\n"
  local token
  token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"

  printf "\n[1b] Ensuring the service account is in the Secrets Hub admin role...\n"
  ensure_user_in_role "$TENANT_ID" "$token" "$CLIENT_ID" "$SECRETSHUB_ADMIN_ROLE" || true

  # Re-mint and wait until Secrets Hub authorizes (mirrors setup.sh [1c]).
  printf "\n[1c] Waiting for Secrets Hub authorization...\n"
  local sh_code
  for _i in $(seq 1 18); do
    token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
    sh_code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --location "https://$subdomain.secretshub.cyberark.cloud/api/secret-stores" \
      --header "Authorization: Bearer $token")"
    if [ "$sh_code" = "200" ]; then
      printf "  Secrets Hub authorized.\n"
      break
    fi
    printf "  not authorized yet (HTTP %s); retrying...\n" "$sh_code"
    sleep 10
  done

  printf "\n[2/4] Removing Secrets Hub sync policy + secret store...\n"
  local store_id
  store_id="$(find_store_id_by_vault_url "$subdomain" "$token" "$AKV_VAULT_URL")"
  if [ -n "$store_id" ]; then
    printf "  found secret store: %s\n" "$store_id"
    delete_store_sync_policies "$subdomain" "$token" "$store_id"
    delete_secret_store "$subdomain" "$token" "$store_id"
  else
    printf "  no matching AZURE_AKV secret store (already removed or never onboarded).\n"
  fi

  printf "\n[3/4] Deleting Privilege Cloud account(s) in Safe %s...\n" "$SAFE_NAME"
  delete_safe_accounts "$subdomain" "$token" "$SAFE_NAME"

  printf "\n[4/4] Deleting Safe %s...\n" "$SAFE_NAME"
  delete_safe "$subdomain" "$token" "$SAFE_NAME" || true

  printf "\nTeardown Azure AKV complete.\n"
  printf "\n%s\n" "$OK_SENTINEL"
}

main "$@"
