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

ensure_tool_installed() {
  local tool_name="$1"
  local install_script="$CYBR_DEMOS_PATH/compute_init/ubuntu/install_${tool_name}.sh"

  if command -v "$tool_name" >/dev/null 2>&1; then
    echo "$tool_name is installed"
  else
    echo "$tool_name is not installed. Installing with $install_script"
    if [ ! -x "$install_script" ]; then
      printf "ERROR: Installer script not found or not executable: %s\n" "$install_script" >&2
      return 1
    fi
    bash "$install_script"
  fi
}

ensure_tool_installed git
ensure_tool_installed curl
ensure_tool_installed jq
