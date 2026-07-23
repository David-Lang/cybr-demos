#!/bin/bash
# Reset the Hardcoded Secret Remediation activity to a clean student-start.
#
# Idempotent. Removes what the student (or solve.sh) created so the activity can
# be run again from scratch:
#   1. delete the PostgreSQL account in the safe (no-op if missing),
#   2. delete the safe (no-op if missing).
#
# It deliberately LEAVES authn-azure and the Conjur workload policy in place:
# those are deployment enablement (set up by setup.sh), not student work.
#
# Invoked ON the VM by the lab app via Azure run-command, which sources the
# tenant creds (TENANT_ID/TENANT_SUBDOMAIN/CLIENT_ID/CLIENT_SECRET/LAB_ID).
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_azure_auth"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Required environment variable is not set: %s\n" "$var_name" >&2
    exit 1
  fi
}

set -a
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"
# shellcheck disable=SC1091
source "$demo_path/activity/inputs.env"
set +a

require_env "TENANT_ID"
require_env "TENANT_SUBDOMAIN"
require_env "CLIENT_ID"
require_env "CLIENT_SECRET"
require_env "SAFE_NAME"

printf "\n========================================\n"
printf "Reset: Hardcoded Secret Remediation\n"
printf "Safe: %s   Account: %s\n" "$SAFE_NAME" "$ACCOUNT_NAME"
printf "========================================\n"

printf "\nAuthenticating to Identity...\n"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\n" >&2
  exit 1
fi
printf "Authentication successful\n"

# --- 1. Delete the onboarded account (no-op if missing) ---------------------
delete_account_by_name "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" "$ACCOUNT_NAME" || \
  printf "WARN: account delete reported an error; continuing.\n" >&2

# --- 2. Delete the safe (no-op / log-and-continue if missing) ---------------
delete_safe "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" || \
  printf "WARN: safe delete reported an error (may not exist); continuing.\n" >&2

printf "\n========================================\n"
printf "Reset complete. Removed (if present):\n"
printf "  - Account: %s\n" "$ACCOUNT_NAME"
printf "  - Safe:    %s\n" "$SAFE_NAME"
printf "Left in place (deployment enablement): authn-azure + the Conjur workload policy.\n"
printf "========================================\n"

printf "__RESET_OK__\n"
