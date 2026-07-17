#!/bin/bash
# shellcheck disable=SC2059
#
# setup.sh — "Onboard Azure AKV" activity orchestrator.
#
# Runs the Idira/CyberArk side of a Secret Stores app-set against an Azure Key
# Vault that the Idira Vegas app already provisioned (AKV + demo secrets +
# standalone rotation-demo app registration). Steps:
#   1. Create the App Safe (Privilege Cloud) + add the Secrets Hub member.
#   2. Vault the rotation-demo app-registration credential as an account.
#   3. Onboard the AKV individually as an AZURE_AKV Secrets Hub store
#      (FEDERATED_IDENTITY, NOT Cloud Connect).
#   4. Create the Secrets Hub sync policy (Safe -> AKV).
#
# Execution: designed to run in a Kubernetes Job that clones cybr-demos and
# invokes this script; also runnable by hand on any host with curl + jq.
#
# Prereqs: export CYBR_DEMOS_PATH and the tenant vars (or set them in
# demos/tenant_vars.sh), then run this script. Activity inputs come from
# ./inputs.env (override with INPUTS_ENV).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUTS_ENV="${INPUTS_ENV:-$SCRIPT_DIR/inputs.env}"

# Success sentinel — the app's Job watcher greps for this (mirrors the Summon
# workshop's __SETUP_VM_OK__). Only printed when every step succeeds (set -e).
OK_SENTINEL="__ONBOARD_AKV_OK__"

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  printf "ERROR: CYBR_DEMOS_PATH is not set. Export it with the path to the cybr-demos repo.\n" >&2
  exit 1
fi

# Loads + validates tenant vars and sources the shared utility functions
# (identity_functions.sh, privilege_functions.sh, ...).
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

# Activity-local Secrets Hub / Azure-account helpers.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

if [ ! -f "$INPUTS_ENV" ]; then
  printf "ERROR: Activity inputs file not found: %s\n" "$INPUTS_ENV" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$INPUTS_ENV"
set +a

require_input() {
  local name="$1" value="${!1:-}"
  if [ -z "$value" ] || [[ "$value" == SET_* ]]; then
    printf "ERROR: required input %s is not set (edit %s or inject it).\n" "$name" "$INPUTS_ENV" >&2
    exit 1
  fi
}

require_input SAFE_NAME
require_input ROTATION_APP_CLIENT_ID
require_input ROTATION_APP_OBJECT_ID
require_input ROTATION_APP_CLIENT_SECRET
require_input AKV_VAULT_NAME
require_input AKV_VAULT_URL
require_input AZURE_TENANT_ID
require_input AZURE_SUBSCRIPTION_ID
require_input AZURE_SUBSCRIPTION_NAME
require_input AZURE_RESOURCE_GROUP
require_input SECRETSHUB_AZURE_APP_CLIENT_ID

# CyberArk Identity role that grants Secrets Hub API access. The service account
# must be a member or the Secrets Hub calls below return 403. Ensured
# automatically (the service account has rights to modify roles).
SECRETSHUB_ADMIN_ROLE="${SECRETSHUB_ADMIN_ROLE:-Secrets Manager - Secrets Hub Admin}"

main() {
  local subdomain="$TENANT_SUBDOMAIN"
  printf "\n== Onboard Azure AKV (%s) — lab %s, tenant %s ==\n" "$AKV_VAULT_NAME" "${LAB_ID:-?}" "$subdomain"

  printf "\n[1/5] Authenticating to CyberArk ISPSS...\n"
  local token
  token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"

  printf "\n[1b] Ensuring the service account is in the Secrets Hub admin role...\n"
  ensure_user_in_role "$TENANT_ID" "$token" "$CLIENT_ID" "$SECRETSHUB_ADMIN_ROLE"

  printf "\n[2/5] Creating App Safe + Secrets Hub member...\n"
  create_safe "$subdomain" "$token" "$SAFE_NAME"
  add_safe_read_member "$subdomain" "$token" "$SAFE_NAME" "$SECRETSHUB_MEMBER"

  printf "\n[3/5] Vaulting rotation-demo app-registration credential...\n"
  vault_azure_app_account "$subdomain" "$token" "$SAFE_NAME" "$ROTATION_ACCOUNT_NAME" \
    "$ROTATION_APP_CLIENT_ID" "$ROTATION_APP_OBJECT_ID" "$ROTATION_APP_CLIENT_SECRET" \
    "$AZURE_TENANT_ID" "$ROTATION_APP_KEY_ID"

  printf "\n[4/5] Onboarding AKV as a Secrets Hub secret store (FEDERATED_IDENTITY)...\n"
  local target_id
  target_id="$(create_azure_akv_store "$subdomain" "$token" "$SECRET_STORE_NAME" \
    "$SECRET_STORE_DESCRIPTION" "$AZURE_TENANT_ID" "$AKV_VAULT_URL" \
    "$SECRETSHUB_AZURE_APP_CLIENT_ID" "$AZURE_SUBSCRIPTION_ID" \
    "$AZURE_SUBSCRIPTION_NAME" "$AZURE_RESOURCE_GROUP")"
  printf "  target store id: %s\n" "$target_id"

  if [ "${CREATE_SYNC_POLICY:-1}" != "1" ]; then
    printf "\n[5/5] Skipping sync policy (CREATE_SYNC_POLICY=%s).\n" "${CREATE_SYNC_POLICY:-}"
    printf "\n%s\n" "$OK_SENTINEL"
    return 0
  fi

  printf "\n[5/5] Creating Secrets Hub sync policy (Safe -> AKV)...\n"
  local source_id policy_id
  source_id="$(get_pcloud_source_store_id "$subdomain" "$token")"
  printf "  source (Privilege Cloud) store id: %s\n" "$source_id"
  policy_id="$(create_sync_policy "$subdomain" "$token" "$SYNC_POLICY_NAME" \
    "$SYNC_POLICY_DESCRIPTION" "$source_id" "$target_id" "$SAFE_NAME")"
  printf "  sync policy id: %s\n" "$policy_id"

  printf "\nOnboard Azure AKV complete.\n"
  printf "\n%s\n" "$OK_SENTINEL"
}

main "$@"
