#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_ubuntu"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name=$SAFE_NAME
workload_name="${WORKLOAD_NAME:-summon-ubuntu}"
workload_id="data/workloads/$workload_name"

echo ""
echo "Conjur setup"
echo "Safe: $safe_name"
echo "Workload: $workload_id"

identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")

workload_policy=$(cat <<POLICY
- !host
  id: $workload_name
  annotations:
    description: Summon Ubuntu workload
POLICY
)

apply_conjur_policy "$isp_subdomain" "$conjur_token" "data/workloads" "$workload_policy" >/dev/null

echo "Rotating API key for workload..."
workload_api_key=$(rotate_workload_api_key "$isp_subdomain" "$conjur_token" "$workload_id")

grant_policy=$(cat <<POLICY
- !grant
  role: !group /$safe_name/delegation/consumers
  member: !host /$workload_id
POLICY
)

patch_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$grant_policy" >/dev/null

creds_file="$demo_path/conjur_credentials.env"
cat > "$creds_file" <<CREDS
# Conjur Credentials for Summon Ubuntu Demo
export CONJUR_APPLIANCE_URL="https://$isp_subdomain.secretsmgr.cyberark.cloud"
export CONJUR_ACCOUNT="conjur"
export CONJUR_AUTHN_LOGIN="host/$workload_id"
export CONJUR_AUTHN_API_KEY="$workload_api_key"
CREDS

chmod 600 "$creds_file"

echo ""
echo "Conjur setup completed successfully"
echo "Credentials file: $creds_file"
echo "Run: source $creds_file"
