#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_aws_auth"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Required environment variable is not set: %s\n" "$var_name" >&2
    exit 1
  fi
}

validate_safe_name() {
  local safe_name="$1"
  local max_length=28
  if [ "${#safe_name}" -gt "$max_length" ]; then
    printf "ERROR: SAFE_NAME exceeds %s characters: %s\n" "$max_length" "$safe_name" >&2
    exit 1
  fi
}

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

require_env "TENANT_ID"
require_env "TENANT_SUBDOMAIN"
require_env "CLIENT_ID"
require_env "CLIENT_SECRET"
require_env "SAFE_NAME"
validate_safe_name "$SAFE_NAME"

printf "\n========================================\n"
printf "Provisioning Safe: %s\n" "$SAFE_NAME"
printf "========================================\n"

printf "\nAuthenticating to Identity...\n"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\n" >&2
  exit 1
fi
printf "Authentication successful\n"

printf "\nCreating safe: %s...\n" "$SAFE_NAME"
create_safe "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME"
printf "Safe created\n"

printf "\nAdding admin role...\n"
add_safe_admin_role "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" "Privilege Cloud Administrators"
printf "Admin role added\n"

printf "\nAdding Conjur Sync member...\n"
add_safe_read_member "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" "Conjur Sync"
printf "Conjur Sync member added\n"

printf "\nCreating demo account...\n"
create_account_ssh_user_1 "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME"
printf "Demo account created\n"

printf "\nWaiting for synchronizer (*/%s/delegation/consumers)...\n" "$SAFE_NAME"
conjur_token="$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")"
if [ -z "$conjur_token" ]; then
  printf "ERROR: Failed to get Conjur token\n" >&2
  exit 1
fi
wait_for_synchronizer "$TENANT_SUBDOMAIN" "$conjur_token" "$SAFE_NAME"
printf "Synchronizer detected safe delegation group\n"

printf "\nSafe setup completed successfully.\n"
