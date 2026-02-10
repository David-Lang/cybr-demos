#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/David-Lang/cybr-demos.git"
BRANCH="main"
DEST="${CYBR_DEMOS_PATH:-/home/ubuntu/cybr-demos}"

# Fresh clone every time (idempotent by replacement)
sudo rm -rf "$DEST"
sudo git clone --depth 1 --single-branch --branch "$BRANCH" "$REPO_URL" "$DEST"
sudo chown -R ubuntu:ubuntu "$DEST"

# Fix ownership if needed
sudo chown -R ubuntu:ubuntu "$DEST"

# Run setup scripts
"$DEST/compute_init/ubuntu/setup.sh"
