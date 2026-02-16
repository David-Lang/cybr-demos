#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/../../../../compute_init/ubuntu/install_summon.sh"

if [ ! -f "$INSTALL_SCRIPT" ]; then
  echo "ERROR: Shared install script not found: $INSTALL_SCRIPT" >&2
  exit 1
fi

echo "Starting Summon installation using shared installer..."
bash "$INSTALL_SCRIPT"
echo "Summon installation completed."
