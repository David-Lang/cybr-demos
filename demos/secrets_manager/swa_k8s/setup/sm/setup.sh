#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] setup/sm/setup.sh is retained for compatibility."
echo "[INFO] Running K8s JWT authenticator setup only."
bash "$SCRIPT_DIR/setup_k8s_auth.sh"
