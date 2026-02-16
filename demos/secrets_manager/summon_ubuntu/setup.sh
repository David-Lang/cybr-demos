#!/bin/bash

# Setup script for: Summon Ubuntu
# Category: secrets_manager

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Setup: Summon Ubuntu"
echo "=========================================="
echo ""

INSTALL_SCRIPT="$SCRIPT_DIR/../../../compute_init/ubuntu/install_summon.sh"
if [ ! -f "$INSTALL_SCRIPT" ]; then
  echo "ERROR: Shared install script not found: $INSTALL_SCRIPT" >&2
  exit 1
fi

echo "Installing Summon and summon-conjur provider..."
bash "$INSTALL_SCRIPT"

echo ""
echo "Installation completed."
echo ""
echo "Next steps:"
echo "   bash ./setup/vault/setup.sh"
echo "   bash ./setup/conjur/setup.sh"
echo "   source ./conjur_credentials.env"
