#!/bin/bash
# Installs the SWA Terraform provider from the release package.
# Idempotent — skips if already installed for the detected OS/arch.

set -euo pipefail

RELEASE_DIR="${SWA_RELEASE_DIR:-}"

if [ -z "$RELEASE_DIR" ]; then
  echo "ERROR: SWA_RELEASE_DIR is not set." >&2
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
