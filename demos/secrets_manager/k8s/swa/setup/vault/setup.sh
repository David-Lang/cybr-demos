#!/bin/bash
# Create the demo safe + account in Privilege Cloud and wait for Conjur Sync to
# replicate it to Conjur Cloud. Idempotent (create calls no-op if they exist).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init

isp_subdomain="$TENANT_SUBDOMAIN"
safe_name="$SAFE_NAME"

echo "[INFO] Acquiring identity token"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
[[ -n "$identity_token" ]] || { echo "[ERROR] identity token empty" >&2; exit 1; }

echo "[INFO] Creating safe '$safe_name' + members"
create_safe "$isp_subdomain" "$identity_token" "$safe_name"
add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"
add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"

echo "[INFO] Creating account-ssh-user-1 in safe '$safe_name'"
create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"

echo "[INFO] Waiting for Conjur Synchronizer (*/$safe_name/delegation/consumers)"
conjur_token="$(get_conjur_token "$isp_subdomain" "$identity_token")"
wait_for_synchronizer "$isp_subdomain" "$conjur_token" "$safe_name"
echo
echo "[INFO] Safe synced to Conjur Cloud."
