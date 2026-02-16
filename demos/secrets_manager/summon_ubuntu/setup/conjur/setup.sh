#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_ubuntu"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Required environment variable is not set: %s\n" "$var_name" >&2
    exit 1
  fi
}

ensure_file() {
  local file_path="$1"
  if [ ! -f "$file_path" ]; then
    printf "ERROR: Required file not found: %s\n" "$file_path" >&2
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
ensure_file "workload.tmpl.yaml"
ensure_file "grant_safe_access.tmpl.yaml"

WORKLOAD_NAME="${WORKLOAD_NAME:-summon-ubuntu}"
WORKLOAD_ID="data/workloads/$WORKLOAD_NAME"

printf "\n========================================\n"
printf "Provisioning Workload: %s\n" "$WORKLOAD_NAME"
printf "========================================\n"
printf "\nSafe: %s\n" "$SAFE_NAME"
printf "Workload: %s\n" "$WORKLOAD_ID"

printf "\nAuthenticating to Identity...\n"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\n" >&2
  exit 1
fi
printf "Authentication successful\n"

printf "\nAuthenticating to Conjur...\n"
conjur_token="$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")"
if [ -z "$conjur_token" ]; then
  printf "ERROR: Failed to get Conjur token\n" >&2
  exit 1
fi
printf "Conjur authentication successful\n"

printf "\nCreating workload policy...\n"
resolve_template "workload.tmpl.yaml" "workload.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data/workloads" "$(cat workload.yaml)" >/dev/null
printf "Workload policy created\n"

printf "\nGranting safe access to workload...\n"
resolve_template "grant_safe_access.tmpl.yaml" "grant_safe_access.yaml"
patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" "$(cat grant_safe_access.yaml)" >/dev/null
printf "Safe access granted\n"

printf "\nRotating API key for workload...\n"
workload_api_key="$(rotate_workload_api_key "$TENANT_SUBDOMAIN" "$conjur_token" "$WORKLOAD_ID")"
if [ -z "$workload_api_key" ]; then
  printf "ERROR: Failed to rotate workload API key\n" >&2
  exit 1
fi
printf "API key rotated\n"

creds_file="$demo_path/conjur_credentials.env"
cat > "$creds_file" <<CREDS
# Conjur Credentials for Summon Ubuntu Demo
export CONJUR_APPLIANCE_URL="https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud"
export CONJUR_ACCOUNT="conjur"
export CONJUR_AUTHN_LOGIN="host/$WORKLOAD_ID"
export CONJUR_AUTHN_API_KEY="$workload_api_key"
CREDS

chmod 600 "$creds_file"

printf "\nConjur setup completed successfully.\n"
printf "Credentials file: %s\n" "$creds_file"
printf "Run: source %s\n" "$creds_file"
