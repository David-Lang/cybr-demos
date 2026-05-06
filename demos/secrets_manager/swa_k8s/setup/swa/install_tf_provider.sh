#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$DEMO_DIR/../../.." && pwd)}"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$DEMO_DIR/setup/vars.env"
set +a

PROVIDER_VERSION="0.1.0-SNAPSHOT"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  TF_ARCH="linux_amd64" ;;
  aarch64) TF_ARCH="linux_arm64" ;;
  *)       echo "ERROR: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

S3_BASE="${SWA_TF_PROVIDER_S3%/}"
BINARY_NAME="terraform-provider-swa_v${PROVIDER_VERSION}"
S3_PATH="${S3_BASE}/terraform-provider-swa_${PROVIDER_VERSION}_${TF_ARCH}/${BINARY_NAME}"
TF_PLUGIN_DIR="${HOME}/.terraform.d/plugins/registry.terraform.io/cyberark/swa/${PROVIDER_VERSION}/${TF_ARCH}"
DEST="${TF_PLUGIN_DIR}/${BINARY_NAME}"

if [[ -x "$DEST" ]]; then
  echo "[INFO] Terraform provider already installed: $DEST"
  exit 0
fi

echo "[INFO] downloading Terraform provider from $S3_PATH"
mkdir -p "$TF_PLUGIN_DIR"
aws s3 cp "$S3_PATH" "$DEST"
chmod +x "$DEST"
echo "[INFO] installed $DEST"
