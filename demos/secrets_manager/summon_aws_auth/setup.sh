#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

printf "==========================================\n"
printf "Setup: Summon AWS Auth\n"
printf "==========================================\n\n"

INSTALL_SCRIPT="$SCRIPT_DIR/../../../compute_init/ubuntu/install_summon.sh"
if [ ! -f "$INSTALL_SCRIPT" ]; then
  printf "ERROR: Shared install script not found: %s\n" "$INSTALL_SCRIPT" >&2
  exit 1
fi

printf "Installing Summon and summon-conjur provider...\n"
bash "$INSTALL_SCRIPT"

printf "\nInstallation completed.\n\n"
printf "Next steps:\n"
printf "   Edit ./setup/vars.env with authn-iam service and AWS region settings\n"
printf "   bash ./setup/vault/setup.sh\n"
printf "   bash ./setup/conjur/setup.sh\n"
printf "   source ./conjur_authn_iam.env\n"
