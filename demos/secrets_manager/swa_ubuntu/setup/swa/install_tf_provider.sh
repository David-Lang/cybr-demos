#!/bin/bash
# Installs the SWA Terraform provider from the release package.
# Idempotent — skips if already installed for the detected OS/arch.

set -euo pipefail

TF_PLUGIN_BASE="${HOME}/.terraform.d/plugins/registry.terraform.io/cyberark/swa"

# Skip install if any version is already present
if find "$TF_PLUGIN_BASE" -name "terraform-provider-swa_v*" -type f 2>/dev/null | grep -q .; then
  echo "      SWA Terraform provider already installed — skipping"
  find "$TF_PLUGIN_BASE" -name "terraform-provider-swa_v*" -type f | head -1
  exit 0
fi

RELEASE_DIR="${SWA_RELEASE_DIR:-}"

if [ -z "$RELEASE_DIR" ] || [[ "$RELEASE_DIR" == "INPUT_REQUIRED" ]]; then
  echo "ERROR: SWA Terraform provider not installed and SWA_RELEASE_DIR is not set." >&2
  echo "       Set it to the path of the extracted swa-release-*.* directory." >&2
  echo "       e.g. export SWA_RELEASE_DIR=~/swa-release-1.0.0" >&2
  exit 1
fi

INSTALLER="${RELEASE_DIR}/install-terraform-provider.sh"
if [ ! -f "$INSTALLER" ]; then
  echo "ERROR: install-terraform-provider.sh not found at $INSTALLER" >&2
  exit 1
fi

bash "$INSTALLER"
