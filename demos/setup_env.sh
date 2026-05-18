#!/bin/bash

# Load tenant credentials and shared helpers. Safe to source from an interactive shell
# only when CYBR_DEMOS_PATH is set and tenant_vars.sh exists. Prefer: bash <demo>/setup.sh

if [[ -z "${CYBR_DEMOS_PATH:-}" ]]; then
  echo "[ERROR] CYBR_DEMOS_PATH is not set. Example: export CYBR_DEMOS_PATH=\"\$(pwd)\"" >&2
  return 1 2>/dev/null || exit 1
fi

# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
if [[ -f "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" ]]; then
  # shellcheck source=/dev/null
  source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
else
  echo "[WARN] Missing $CYBR_DEMOS_PATH/demos/tenant_vars.sh — create it from README.md (tenant credentials)." >&2
fi
# shellcheck source=/dev/null
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/conjur_functions.sh"
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/privilege_functions.sh"
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/template_functions.sh"
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/aws_functions.sh"
set +a

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
