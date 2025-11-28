#!/bin/bash

# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
source "$CYBR_DEMOS_PATH/demos/setup_vars.env"
source "$CYBR_DEMOS_PATH/demos/setup_functions/identity_functions.sh"
source "$CYBR_DEMOS_PATH/demos/setup_functions/conjur_functions.sh"
source "$CYBR_DEMOS_PATH/demos/setup_functions/vault_functions.sh"
source "$CYBR_DEMOS_PATH/demos/setup_functions/template_functions.sh"
source "$CYBR_DEMOS_PATH/demos/setup_functions/asset_functions.sh"
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
