#!/bin/bash
# Automated "answer" for the Hardcoded Secret Remediation activity.
#
# Idempotent. Performs the student's manual vault + grant + verify steps so the
# finished state can be inspected and the secured query can be run:
#   0. create the per-VM authn-azure workload record (host + apps grant),
#   1. create the safe (named after the VM),
#   2. add the "Conjur Sync" member so Secrets Manager syncs the safe,
#   3. onboard the PostgreSQL account exposing username + password,
#   4. grant this VM's workload identity read access (Consumers group),
#   5. best-effort verify the secured query returns rows.
#
# It DOES NOT rotate the credential — rotation is the live/manual capstone.
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

validate_safe_name() {
  local safe_name="$1"
  local max_length=28
  if [ "${#safe_name}" -gt "$max_length" ]; then
    printf "ERROR: SAFE_NAME exceeds %s characters: %s\n" "$max_length" "$safe_name" >&2
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
validate_safe_name "$SAFE_NAME"

printf "\n========================================\n"
printf "Solve: Hardcoded Secret Remediation\n"
printf "Safe: %s   Account: %s\n" "$SAFE_NAME" "$ACCOUNT_NAME"
printf "========================================\n"

printf "\nAuthenticating to Identity...\n"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\n" >&2
  exit 1
fi
printf "Authentication successful\n"

# Resolve the Idira user the automation runs as (for the safe description).
idira_user="$(get_service_user_name "$TENANT_ID" "$identity_token" 2>/dev/null || true)"
[ -n "$idira_user" ] || idira_user="Idira automation"
safe_description="Hardcoded Secret Remediation activity - solved by ${idira_user}"

# --- 0. Workload record (authn-azure host) ----------------------------------
# Create the per-VM workload BEFORE vaulting. Without it authn-azure can
# authenticate the VM's managed-identity token but has no workload to map it to,
# so the vaulted credential would be unreadable. Idempotent; fail solve if it
# fails (the vault is pointless without the workload).
printf "\nCreating the authn-azure workload record...\n"
bash "$demo_path/setup/conjur/workload.sh" create

# Ensure the PostgreSQL target platform is active (best-effort; account onboarding
# fails under an inactive platform).
printf "\nEnsuring platform '%s' is active...\n" "$POSTGRES_PLATFORM_ID"
ensure_platform_active "$TENANT_SUBDOMAIN" "$identity_token" "$POSTGRES_PLATFORM_ID" || \
  printf "WARN: could not confirm platform '%s' is active; continuing.\n" "$POSTGRES_PLATFORM_ID" >&2

# --- 1. Safe (skip if it already exists) ------------------------------------
safe_lookup="$(curl --silent --location \
  "https://$TENANT_SUBDOMAIN.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$SAFE_NAME" \
  --header "Authorization: Bearer $identity_token" --header "Accept: application/json")"
existing_safe="$(printf '%s' "$safe_lookup" | jq -r '.safeName // empty' 2>/dev/null)"
if [ -n "$existing_safe" ]; then
  printf "\nSafe '%s' already exists; skipping create.\n" "$SAFE_NAME"
else
  create_safe "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" "$safe_description"
  printf "\nSafe '%s' created (%s).\n" "$SAFE_NAME" "$safe_description"
fi

# --- 1b. Safe admin role (idempotent) ---------------------------------------
# Add the "Privilege Cloud Administrators" role as a full admin member so Idira
# administrators (who belong to that role) can manage the safe. Adding an
# existing member returns an error body; harmless, so keep going.
add_safe_admin_role "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" "Privilege Cloud Administrators" || true
printf "\n'Privilege Cloud Administrators' admin role ensured on safe '%s'.\n" "$SAFE_NAME"

# --- 2. Conjur Sync member (idempotent) -------------------------------------
# Adding an already-present member returns an error body; that is harmless, so
# keep going.
add_safe_read_member "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" "Conjur Sync" || true
printf "\nConjur Sync member ensured on safe '%s'.\n" "$SAFE_NAME"

# --- 3. PostgreSQL account (skip if present) --------------------------------
existing_account_id="$(account_id_by_name "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" "$ACCOUNT_NAME")"
if [ -n "$existing_account_id" ] && [ "$existing_account_id" != "null" ]; then
  printf "\nAccount '%s' already exists in safe '%s' (id %s); skipping create.\n" \
    "$ACCOUNT_NAME" "$SAFE_NAME" "$existing_account_id"
else
  create_postgres_account "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" \
    "$ACCOUNT_NAME" "$DB_USERNAME" "$DB_PASSWORD" "$ROTATION_ADDRESS" \
    "$POSTGRES_PLATFORM_ID" "$DB_PORT" "$DB_NAME"
  printf "\nAccount '%s' onboarded in safe '%s'.\n" "$ACCOUNT_NAME" "$SAFE_NAME"
fi

# --- 4. Consumers grant (waits for sync, applies consumers_grant policy) -----
printf "\nGranting the workload read access to the safe consumers group...\n"
bash "$demo_path/setup/conjur/grant_consumers.sh"

# --- 5. Verify (best-effort, non-fatal) -------------------------------------
LABS_ROOT="${LABS_ROOT:-/opt/labs}"
STUDENT_PREFIX="${STUDENT_PREFIX:-student}"
ACTIVITY_DIR_NAME="${ACTIVITY_DIR_NAME:-hardcoded-secret-remediation}"
student_dir="$LABS_ROOT/${STUDENT_PREFIX}1/$ACTIVITY_DIR_NAME"

printf "\n----------------------------------------\n"
printf "Verifying the secured query...\n"
printf "----------------------------------------\n"
if [ -x "$student_dir/run_secured_query.sh" ]; then
  if (cd "$student_dir" && ./run_secured_query.sh); then
    printf "\nVERIFY PASS: run_secured_query.sh returned rows using the vaulted credential.\n"
  else
    printf "\nVERIFY WARN: run_secured_query.sh did not succeed yet.\n" >&2
    printf "The account may still be syncing; re-run: (cd %s && ./run_secured_query.sh)\n" "$student_dir" >&2
  fi
else
  printf "\nStudent workspace not found at %s; skipping automated verify.\n" "$student_dir"
  if [ -f "$demo_path/conjur_authn_azure.env" ]; then
    # shellcheck disable=SC1091
    source "$demo_path/conjur_authn_azure.env"
    printf "Sourced conjur_authn_azure.env. Verify manually with Summon once the workspace is rendered.\n"
  fi
fi

printf "\n========================================\n"
printf "Solve complete. Created / ensured:\n"
printf "  - Workload:        data/%s/azure-apps/%s (authn-azure)\n" "${LAB_ID:-<lab>}" "${AZURE_WORKLOAD_HOST_NAME:-<vm-identity>}"
printf "  - Safe:            %s\n" "$SAFE_NAME"
printf "  - Safe admin role: Privilege Cloud Administrators\n"
printf "  - Safe member:     Conjur Sync\n"
printf "  - Account:         %s (user %s, platform %s, address %s)\n" \
  "$ACCOUNT_NAME" "$DB_USERNAME" "$POSTGRES_PLATFORM_ID" "$ROTATION_ADDRESS"
printf "  - Consumers grant: workload -> vault/%s/delegation/consumers\n" "$SAFE_NAME"
printf "Rotation was NOT performed (that is the live/manual capstone).\n"
printf "========================================\n"

printf "__SOLVE_OK__\n"
