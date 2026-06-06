#!/bin/bash
# Installs the SWA Terraform provider from S3.
# Idempotent — skips if already installed for the detected OS/arch.

set -euo pipefail

PROVIDER_VERSION="0.1.0-SNAPSHOT"
S3_BASE="s3://mis-cybr-demos/pm/terraform-provider"
TF_PLUGIN_BASE="${HOME}/.terraform.d/plugins/registry.terraform.io/cyberark/swa"

# Skip install if any version is already present
if find "$TF_PLUGIN_BASE" -name "terraform-provider-swa_v*" -type f 2>/dev/null | grep -q .; then
  echo "      SWA Terraform provider already installed — skipping"
  find "$TF_PLUGIN_BASE" -name "terraform-provider-swa_v*" -type f | head -1
  exit 0
fi

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="linux_amd64" ;;
  aarch64) BIN_ARCH="linux_arm64" ;;
  *)       echo "ERROR: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

BINARY_NAME="terraform-provider-swa_v${PROVIDER_VERSION}"
S3_PATH="${S3_BASE}/terraform-provider-swa_${PROVIDER_VERSION}_${BIN_ARCH}/${BINARY_NAME}"
TF_PLUGIN_DIR="${TF_PLUGIN_BASE}/${PROVIDER_VERSION}/${BIN_ARCH}"
DEST="${TF_PLUGIN_DIR}/${BINARY_NAME}"

echo "      Downloading from ${S3_PATH}..."
mkdir -p "$TF_PLUGIN_DIR"
aws s3 cp "$S3_PATH" "$DEST"
chmod +x "$DEST"
echo "      ${DEST}   OK"
