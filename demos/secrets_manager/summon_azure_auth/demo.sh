#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SECRETS_FILE="$SCRIPT_DIR/secrets.yml"

if [ -f "$SCRIPT_DIR/conjur_authn_azure.env" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/conjur_authn_azure.env"
fi

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
  encoded_resource="$(url_encode "${AZURE_IMDS_RESOURCE:-https://management.azure.com/}")"
  url="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${encoded_resource}"

  if [ -n "${AZURE_CLIENT_ID:-}" ]; then
    encoded_client_id="$(url_encode "$AZURE_CLIENT_ID")"
    url="${url}&client_id=${encoded_client_id}"
  fi

  curl --fail --silent --show-error --connect-timeout 2 --max-time 15 \
    --header "Metadata: true" \
    "$url"
}

required_vars=(
  CONJUR_APPLIANCE_URL
  CONJUR_ACCOUNT
)

for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Missing required environment variable: %s\n" "$var_name" >&2
    printf "Run bash ./setup/conjur/setup.sh and source ./conjur_authn_azure.env\n" >&2
    exit 1
  fi
done

if [ ! -f "$SECRETS_FILE" ]; then
  printf "ERROR: Resolved secrets file not found: %s\n" "$SECRETS_FILE" >&2
  printf "Run ./setup.sh to render the runtime secrets file.\n" >&2
  exit 1
fi

require_command "curl"
require_command "jq"
require_command "summon"

if [ ! -x "/usr/local/lib/summon/summon-conjur" ] && ! command -v summon-conjur >/dev/null 2>&1; then
  printf "ERROR: summon-conjur provider is not installed\n" >&2
  exit 1
fi

if [ -z "${CONJUR_AUTHN_TYPE:-}" ]; then
  export CONJUR_AUTHN_TYPE="azure"
fi

if [ -z "${CONJUR_SERVICE_ID:-}" ] && [ -n "${AUTHN_AZURE_SERVICE_ID:-}" ]; then
  export CONJUR_SERVICE_ID="$AUTHN_AZURE_SERVICE_ID"
fi

if [ -z "${CONJUR_AUTHN_JWT_HOST_ID:-}" ] && [ -n "${WORKLOAD_HOST_ID:-}" ]; then
  export CONJUR_AUTHN_JWT_HOST_ID="$WORKLOAD_HOST_ID"
fi

if [ -z "${CONJUR_AUTHN_JWT_HOST_ID:-}" ] && [ -n "${CONJUR_AUTHN_LOGIN:-}" ]; then
  export CONJUR_AUTHN_JWT_HOST_ID="${CONJUR_AUTHN_LOGIN#host/}"
fi

cloud_required_vars=(
  CONJUR_AUTHN_TYPE
  CONJUR_SERVICE_ID
  CONJUR_AUTHN_JWT_HOST_ID
)

for var_name in "${cloud_required_vars[@]}"; do
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Missing required cloud auth variable: %s\n" "$var_name" >&2
    printf "Run bash ./setup/conjur/setup.sh and source ./conjur_authn_azure.env\n" >&2
    exit 1
  fi
done

printf "==========================================\n"
printf "Demo: Summon Azure Auth (post-vault smoke test)\n"
printf "==========================================\n\n"
printf "Retrieves the vaulted Postgres credential via Summon to prove the secured\n"
printf "path works. Requires the student to have vaulted the account and the\n"
printf "workload to have been granted access (setup/conjur/grant_consumers.sh).\n\n"

printf "Conjur appliance: %s\n" "$CONJUR_APPLIANCE_URL"
printf "Conjur authn type: %s\n" "$CONJUR_AUTHN_TYPE"
printf "Conjur service id: %s\n" "$CONJUR_SERVICE_ID"
printf "Conjur host id: %s\n\n" "$CONJUR_AUTHN_JWT_HOST_ID"

printf "Azure managed identity token metadata:\n"
azure_identity_json="$(azure_imds_token_response)"
printf "%s" "$azure_identity_json" | jq '{client_id, resource, token_type, expires_on}'
printf "\n"

if [ "${SUMMON_AZURE_FETCH_TOKEN:-false}" = "true" ]; then
  export CONJUR_AUTHN_JWT_TOKEN
  CONJUR_AUTHN_JWT_TOKEN="$(printf "%s" "$azure_identity_json" | jq -r '.access_token')"
  if [ -z "$CONJUR_AUTHN_JWT_TOKEN" ] || [ "$CONJUR_AUTHN_JWT_TOKEN" = "null" ]; then
    printf "ERROR: Failed to extract Azure access token from IMDS response\n" >&2
    exit 1
  fi
  printf "Using explicit CONJUR_AUTHN_JWT_TOKEN from Azure IMDS for this Summon invocation.\n\n"
else
  printf "Leaving Azure token retrieval to summon-conjur metadata support.\n\n"
fi

summon --provider summon-conjur -f "$SECRETS_FILE" bash "$SCRIPT_DIR/consumer.sh"
