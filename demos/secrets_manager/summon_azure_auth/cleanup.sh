#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_azure_auth"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

if [ -f /etc/profile.d/cyberark.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Required environment variable is not set: %s\n" "$var_name" >&2
    exit 1
  fi
}

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

required_vars=(
  LAB_ID
  TENANT_ID
  TENANT_SUBDOMAIN
  CLIENT_ID
  CLIENT_SECRET
  SAFE_NAME
)

for var_name in "${required_vars[@]}"; do
  require_env "$var_name"
done

WORKLOAD_POLICY_ID="data/$LAB_ID/azure-apps"

printf "\nAuthenticating to Identity...\n"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\n" >&2
  exit 1
fi

printf "Authenticating to Conjur...\n"
conjur_token="$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")"
if [ -z "$conjur_token" ]; then
  printf "ERROR: Failed to get Conjur token\n" >&2
  exit 1
fi

printf "\nRemoving workload policy: %s\n" "$WORKLOAD_POLICY_ID"
patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data/$LAB_ID" "$(cat <<EOF
# metadata
# mode: append-policy
---
- !delete
  record: !policy azure-apps
EOF
)" >/dev/null || true

printf "Deleting demo account and safe: %s\n" "$SAFE_NAME"
delete_account_ssh_user_1 "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" >/dev/null || true
delete_safe "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" >/dev/null || true

rm -f "$demo_path/conjur_authn_azure.env"
rm -f "$demo_path/secrets.yml"
rm -rf "$script_dir/artifacts"

printf "\nCleanup completed.\n"
printf "Left authn-azure service in place: authn-azure/%s\n" "${AUTHN_AZURE_SERVICE_ID:-<unset>}"
