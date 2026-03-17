#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_aws_auth"
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
)

for var_name in "${required_vars[@]}"; do
  require_env "$var_name"
done

require_command "aws"
require_command "jq"

printf "\nResolving AWS caller identity for cleanup...\n"
aws_identity_json="$(aws sts get-caller-identity --output json)"
AWS_ACCOUNT_ID="$(get_aws_identity_field "$aws_identity_json" "Account")"
AWS_CALLER_ARN="$(get_aws_identity_field "$aws_identity_json" "Arn")"
AWS_ROLE_NAME="$(get_role_path_from_arn "$AWS_CALLER_ARN")"
WORKLOAD_POLICY_ID="data/$LAB_ID"
WORKLOAD_HOST_ID="$WORKLOAD_POLICY_ID/$AWS_ACCOUNT_ID/$AWS_ROLE_NAME"

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

printf "\nRemoving workload host: %s\n" "$WORKLOAD_HOST_ID"
patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" "$(cat <<EOF
# metadata
# mode: append-policy
---
- !delete
  record: !policy /$WORKLOAD_POLICY_ID
EOF
)" >/dev/null || true

printf "Deleting demo account and safe: %s\n" "$SAFE_NAME"
delete_account_ssh_user_1 "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" >/dev/null || true
delete_safe "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" >/dev/null || true

rm -f "$demo_path/conjur_authn_iam.env"
rm -rf "$script_dir/artifacts"

printf "\nCleanup completed.\n"
