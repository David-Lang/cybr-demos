#!/bin/bash

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  printf "ERROR: CYBR_DEMOS_PATH is not set. Export it with the path to this repo.\n" >&2
  return 1 2>/dev/null || exit 1
fi

# Export assignments from sourced environment files.
set -a
if [ -f /etc/profile.d/cyberark.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

if [ -f "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" ]; then
  # shellcheck disable=SC1091
  source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
fi
set +a

require_real_env() {
  local var_name="$1"
  local var_value="${!var_name:-}"

  if [ -z "$var_value" ] || [[ "$var_value" == SET_* ]]; then
    printf "ERROR: %s is not set. Set it in the environment or demos/tenant_vars.sh.\n" "$var_name" >&2
    return 1
  fi
}

required_tenant_vars=(
  LAB_ID
  TENANT_ID
  TENANT_SUBDOMAIN
  CLIENT_ID
  CLIENT_SECRET
)

for var_name in "${required_tenant_vars[@]}"; do
  require_real_env "$var_name" || return 1 2>/dev/null || exit 1
done

# Source shared helper functions after tenant validation so failures are clear.
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/conjur_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/privilege_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/template_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/aws_functions.sh"

is_tool_installed() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "$1 is installed"
  else
    echo "$1 is not installed and it might be required to run setup scripts"
  fi
}

is_tool_installed git
is_tool_installed curl
is_tool_installed jq
