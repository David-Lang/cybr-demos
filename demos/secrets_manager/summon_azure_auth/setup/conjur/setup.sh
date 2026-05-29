#!/bin/bash
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

ensure_file() {
  local file_path="$1"
  if [ ! -f "$file_path" ]; then
    printf "ERROR: Required file not found: %s\n" "$file_path" >&2
    exit 1
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf "ERROR: Required command is not installed: %s\n" "$command_name" >&2
    exit 1
  fi
}

url_encode() {
  jq -rn --arg value "$1" '$value|@uri'
}

azure_imds_token_response() {
  local encoded_resource encoded_client_id url
  encoded_resource="$(url_encode "$AZURE_IMDS_RESOURCE")"
  url="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${encoded_resource}"

  if [ -n "${AZURE_CLIENT_ID:-}" ]; then
    encoded_client_id="$(url_encode "$AZURE_CLIENT_ID")"
    url="${url}&client_id=${encoded_client_id}"
  fi

  curl --fail --silent --show-error --connect-timeout 2 --max-time 15 \
    --header "Metadata: true" \
    "$url"
}

validate_azure_imds() {
  local token_json token_value

  if ! token_json="$(azure_imds_token_response)"; then
    printf "ERROR: Failed to retrieve Azure managed identity token from IMDS.\n" >&2
    if [ -z "${AZURE_CLIENT_ID:-}" ]; then
      printf "If this VM has multiple identities, set AZURE_CLIENT_ID in setup/vars.env.\n" >&2
    fi
    exit 1
  fi

  token_value="$(printf "%s" "$token_json" | jq -r '.access_token // empty')"
  if [ -z "$token_value" ]; then
    printf "ERROR: Azure IMDS response did not include access_token\n" >&2
    printf "%s\n" "$token_json" | jq . >&2
    exit 1
  fi

  printf "%s" "$token_json" | jq '{client_id, resource, token_type, expires_on}'
}

authn_azure_apps_group_exists() {
  get_conjur_groups "$TENANT_SUBDOMAIN" "$conjur_token" \
    | grep -F "conjur/authn-azure/$AUTHN_AZURE_SERVICE_ID/apps" >/dev/null 2>&1
}

warn_identity_name_constraints() {
  local identity_name="$1"
  if [ "${#identity_name}" -gt 24 ]; then
    printf "WARNING: CyberArk Azure examples recommend a user-assigned identity name of 24 or fewer characters.\n" >&2
    printf "Current AZURE_USER_ASSIGNED_IDENTITY_NAME is %s characters: %s\n" "${#identity_name}" "$identity_name" >&2
  fi
}

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

AZURE_IMDS_RESOURCE="${AZURE_IMDS_RESOURCE:-https://management.azure.com/}"
AZURE_WORKLOAD_HOST_NAME="${AZURE_WORKLOAD_HOST_NAME:-}"
if [ -z "$AZURE_WORKLOAD_HOST_NAME" ]; then
  AZURE_WORKLOAD_HOST_NAME="$AZURE_USER_ASSIGNED_IDENTITY_NAME"
fi
AZURE_PROVIDER_URI="https://sts.windows.net/$AZURE_TENANT_ID/"
WORKLOAD_POLICY_BRANCH="data"
WORKLOAD_APP_GROUP_ID="data/$LAB_ID/azure-apps"
WORKLOAD_HOST_ID="$WORKLOAD_APP_GROUP_ID/$AZURE_WORKLOAD_HOST_NAME"

required_vars=(
  LAB_ID
  TENANT_ID
  TENANT_SUBDOMAIN
  CLIENT_ID
  CLIENT_SECRET
  SAFE_NAME
  AUTHN_AZURE_SERVICE_ID
  AZURE_TENANT_ID
  AZURE_SUBSCRIPTION_ID
  AZURE_RESOURCE_GROUP
  AZURE_USER_ASSIGNED_IDENTITY_NAME
  AZURE_WORKLOAD_HOST_NAME
  AZURE_IMDS_RESOURCE
)

for var_name in "${required_vars[@]}"; do
  require_env "$var_name"
done
validate_safe_name "$SAFE_NAME"
warn_identity_name_constraints "$AZURE_USER_ASSIGNED_IDENTITY_NAME"

require_command "curl"
require_command "jq"
ensure_file "authenticator_service.tmpl.yaml"
ensure_file "workload.tmpl.yaml"
ensure_file "authenticator_grant.tmpl.yaml"

printf "\nResolving Azure managed identity through IMDS...\n"
validate_azure_imds

printf "\n========================================\n"
printf "Provisioning Azure Managed Identity Workload\n"
printf "========================================\n"
printf "\nSafe: %s\n" "$SAFE_NAME"
printf "Authn service: %s\n" "$AUTHN_AZURE_SERVICE_ID"
printf "Provider URI: %s\n" "$AZURE_PROVIDER_URI"
printf "Azure subscription: %s\n" "$AZURE_SUBSCRIPTION_ID"
printf "Azure resource group: %s\n" "$AZURE_RESOURCE_GROUP"
printf "Azure identity name: %s\n" "$AZURE_USER_ASSIGNED_IDENTITY_NAME"
printf "Workload group: %s\n" "$WORKLOAD_APP_GROUP_ID"
printf "Workload host: %s\n" "$WORKLOAD_HOST_ID"

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

if authn_azure_apps_group_exists; then
  printf "\nAzure authenticator service already exists: authn-azure/%s\n" "$AUTHN_AZURE_SERVICE_ID"
else
  printf "\nCreating Azure authenticator service policy: authn-azure/%s...\n" "$AUTHN_AZURE_SERVICE_ID"
  resolve_template "authenticator_service.tmpl.yaml" "authenticator_service.yaml"
  apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-azure" "$(cat authenticator_service.yaml)" >/dev/null
  printf "Azure authenticator service policy created\n"
fi

printf "\nSetting Azure provider URI...\n"
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-azure/$AUTHN_AZURE_SERVICE_ID/provider-uri" "$AZURE_PROVIDER_URI" >/dev/null
printf "provider-uri set\n"

printf "\nEnabling authn-azure service: %s...\n" "$AUTHN_AZURE_SERVICE_ID"
activate_conjur_service "$TENANT_SUBDOMAIN" "$conjur_token" "authn-azure/$AUTHN_AZURE_SERVICE_ID" >/dev/null
printf "authn-azure service enabled\n"

printf "\nCreating workload policy...\n"
resolve_template "workload.tmpl.yaml" "workload.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "$WORKLOAD_POLICY_BRANCH" "$(cat workload.yaml)" >/dev/null
printf "Workload policy created\n"

printf "\nGranting workload access to authn-azure apps...\n"
resolve_template "authenticator_grant.tmpl.yaml" "authenticator_grant.yaml"
patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-azure" "$(cat authenticator_grant.yaml)" >/dev/null
printf "authn-azure apps grant applied\n"

creds_file="$demo_path/conjur_authn_azure.env"
cat > "$creds_file" <<CREDS
# Conjur authn-azure environment for Summon Azure Auth demo
export CONJUR_APPLIANCE_URL="https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud"
export CONJUR_ACCOUNT="conjur"
export CONJUR_AUTHN_TYPE="azure"
export CONJUR_SERVICE_ID="$AUTHN_AZURE_SERVICE_ID"
export CONJUR_AUTHN_JWT_HOST_ID="$WORKLOAD_HOST_ID"
export CONJUR_AUTHN_LOGIN="host/$WORKLOAD_HOST_ID"
export CONJUR_AUTHN_URL="https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn-azure/$AUTHN_AZURE_SERVICE_ID/conjur"
export AUTHN_AZURE_SERVICE_ID="$AUTHN_AZURE_SERVICE_ID"
export WORKLOAD_APP_GROUP_ID="$WORKLOAD_APP_GROUP_ID"
export WORKLOAD_HOST_ID="$WORKLOAD_HOST_ID"
export AZURE_PROVIDER_URI="$AZURE_PROVIDER_URI"
export AZURE_TENANT_ID="$AZURE_TENANT_ID"
export AZURE_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
export AZURE_RESOURCE_GROUP="$AZURE_RESOURCE_GROUP"
export AZURE_USER_ASSIGNED_IDENTITY_NAME="$AZURE_USER_ASSIGNED_IDENTITY_NAME"
export AZURE_WORKLOAD_HOST_NAME="$AZURE_WORKLOAD_HOST_NAME"
export AZURE_CLIENT_ID="$AZURE_CLIENT_ID"
export AZURE_IMDS_RESOURCE="$AZURE_IMDS_RESOURCE"
export SUMMON_AZURE_FETCH_TOKEN="$SUMMON_AZURE_FETCH_TOKEN"
CREDS

chmod 600 "$creds_file"

printf "\nConjur setup completed successfully.\n"
printf "Credentials file: %s\n" "$creds_file"
printf "Run: source %s\n" "$creds_file"
