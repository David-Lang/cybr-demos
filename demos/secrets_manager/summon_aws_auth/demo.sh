#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SECRETS_FILE="$SCRIPT_DIR/secrets.yml"

if [ -f "$SCRIPT_DIR/conjur_authn_iam.env" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/conjur_authn_iam.env"
fi

required_vars=(
  CONJUR_APPLIANCE_URL
  CONJUR_ACCOUNT
)

for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Missing required environment variable: %s\n" "$var_name" >&2
    printf "Run bash ./setup/conjur/setup.sh and source ./conjur_authn_iam.env\n" >&2
    exit 1
  fi
done

if [ ! -f "$SECRETS_FILE" ]; then
  printf "ERROR: Resolved secrets file not found: %s\n" "$SECRETS_FILE" >&2
  printf "Run ./setup.sh to render the runtime secrets file.\n" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  printf "ERROR: aws CLI is required for AWS IAM authentication\n" >&2
  exit 1
fi

if ! command -v summon >/dev/null 2>&1; then
  printf "ERROR: summon is not installed\n" >&2
  exit 1
fi

if [ ! -x "/usr/local/lib/summon/summon-conjur" ] && ! command -v summon-conjur >/dev/null 2>&1; then
  printf "ERROR: summon-conjur provider is not installed\n" >&2
  exit 1
fi

if [ -z "${CONJUR_AUTHN_TYPE:-}" ]; then
  export CONJUR_AUTHN_TYPE="iam"
fi

if [ -z "${CONJUR_SERVICE_ID:-}" ] && [ -n "${AUTHN_IAM_SERVICE_ID:-}" ]; then
  export CONJUR_SERVICE_ID="$AUTHN_IAM_SERVICE_ID"
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
    printf "Run bash ./setup/conjur/setup.sh and source ./conjur_authn_iam.env\n" >&2
    exit 1
  fi
done

printf "==========================================\n"
printf "Demo: Summon AWS Auth\n"
printf "==========================================\n\n"

printf "Conjur appliance: %s\n" "$CONJUR_APPLIANCE_URL"
printf "Conjur authn type: %s\n" "$CONJUR_AUTHN_TYPE"
printf "Conjur service id: %s\n" "$CONJUR_SERVICE_ID"
printf "Conjur host id: %s\n\n" "$CONJUR_AUTHN_JWT_HOST_ID"

printf "AWS caller identity:\n"
aws sts get-caller-identity
printf "\n"

summon --provider summon-conjur -f "$SECRETS_FILE" bash "$SCRIPT_DIR/consumer.sh"
