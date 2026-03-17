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

get_aws_identity_field() {
  local identity_json="$1"
  local field_name="$2"
  printf "%s" "$identity_json" | jq -r ".$field_name"
}

get_role_path_from_arn() {
  local arn="$1"
  local role_path

  case "$arn" in
    arn:aws:sts::*:assumed-role/*)
      role_path="${arn#*:assumed-role/}"
      role_path="${role_path%/*}"
      ;;
    arn:aws:iam::*:role/*)
      role_path="${arn#*:role/}"
      ;;
    *)
      printf "ERROR: Unsupported AWS caller ARN for authn-iam demo: %s\n" "$arn" >&2
      printf "Expected an assumed-role or role ARN.\n" >&2
      exit 1
      ;;
  esac

  if [ -z "$role_path" ]; then
    printf "ERROR: Failed to derive role path from ARN: %s\n" "$arn" >&2
    exit 1
  fi

  printf "%s" "$role_path"
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
  AUTHN_IAM_SERVICE_ID
  AWS_REGION
)

for var_name in "${required_vars[@]}"; do
  require_env "$var_name"
done
validate_safe_name "$SAFE_NAME"

require_command "aws"
require_command "jq"
ensure_file "workload.tmpl.yaml"
ensure_file "authenticator_grant.tmpl.yaml"

printf "\nResolving AWS caller identity...\n"
aws_identity_json="$(aws sts get-caller-identity --output json)"
AWS_ACCOUNT_ID="$(get_aws_identity_field "$aws_identity_json" "Account")"
AWS_CALLER_ARN="$(get_aws_identity_field "$aws_identity_json" "Arn")"
AWS_ROLE_NAME="$(get_role_path_from_arn "$AWS_CALLER_ARN")"

if [ -z "$AWS_ACCOUNT_ID" ] || [ "$AWS_ACCOUNT_ID" = "null" ]; then
  printf "ERROR: Failed to resolve AWS account ID from sts get-caller-identity\n" >&2
  exit 1
fi

if [ -z "$AWS_CALLER_ARN" ] || [ "$AWS_CALLER_ARN" = "null" ]; then
  printf "ERROR: Failed to resolve AWS caller ARN from sts get-caller-identity\n" >&2
  exit 1
fi

WORKLOAD_POLICY_BRANCH="data"
WORKLOAD_HOST_ID="data/$LAB_ID/$AWS_ACCOUNT_ID/$AWS_ROLE_NAME"

printf "\n========================================\n"
printf "Provisioning AWS IAM Workload\n"
printf "========================================\n"
printf "\nSafe: %s\n" "$SAFE_NAME"
printf "Authn service: %s\n" "$AUTHN_IAM_SERVICE_ID"
printf "AWS caller ARN: %s\n" "$AWS_CALLER_ARN"
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

printf "\nEnabling authn-iam service: %s...\n" "$AUTHN_IAM_SERVICE_ID"
activate_conjur_service "$TENANT_SUBDOMAIN" "$conjur_token" "authn-iam/$AUTHN_IAM_SERVICE_ID" >/dev/null
printf "authn-iam service enabled\n"

printf "\nCreating workload policy...\n"
resolve_template "workload.tmpl.yaml" "workload.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "$WORKLOAD_POLICY_BRANCH" "$(cat workload.yaml)" >/dev/null
printf "Workload policy created\n"

printf "\nGranting workload access to authn-iam consumers...\n"
resolve_template "authenticator_grant.tmpl.yaml" "authenticator_grant.yaml"
patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-iam" "$(cat authenticator_grant.yaml)" >/dev/null
printf "authn-iam consumer grant applied\n"

creds_file="$demo_path/conjur_authn_iam.env"
cat > "$creds_file" <<CREDS
# Conjur authn-iam environment for Summon AWS Auth demo
export CONJUR_APPLIANCE_URL="https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud"
export CONJUR_ACCOUNT="conjur"
export CONJUR_AUTHN_TYPE="iam"
export CONJUR_SERVICE_ID="$AUTHN_IAM_SERVICE_ID"
export CONJUR_AUTHN_JWT_HOST_ID="$WORKLOAD_HOST_ID"
export CONJUR_AUTHN_LOGIN="host/$WORKLOAD_HOST_ID"
export CONJUR_AUTHN_URL="https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn-iam/$AUTHN_IAM_SERVICE_ID/conjur"
export AUTHN_IAM_SERVICE_ID="$AUTHN_IAM_SERVICE_ID"
export WORKLOAD_HOST_ID="$WORKLOAD_HOST_ID"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export AWS_ROLE_NAME="$AWS_ROLE_NAME"
export AWS_CALLER_ARN="$AWS_CALLER_ARN"
export AWS_REGION="$AWS_REGION"
CREDS

chmod 600 "$creds_file"

printf "\nConjur setup completed successfully.\n"
printf "Credentials file: %s\n" "$creds_file"
printf "Run: source %s\n" "$creds_file"
