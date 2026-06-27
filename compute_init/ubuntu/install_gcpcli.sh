#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log(){ echo "[INFO] $*"; }

if ! sudo -n true 2>/dev/null; then
  echo "[ERROR] sudo requires a password (would prompt). Configure passwordless sudo or run as root." >&2
  exit 1
fi

if command -v gcloud >/dev/null 2>&1; then
  log "Google Cloud CLI already installed: $(gcloud --version | head -1)"
  exit 0
fi

log "Installing Google Cloud CLI"

sudo -n apt-get update -qq
sudo -n apt-get install -y -qq apt-transport-https ca-certificates gnupg curl

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | gpg --dearmor \
  | sudo -n tee /usr/share/keyrings/cloud.google.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo -n tee /etc/apt/sources.list.d/google-cloud-sdk.list

sudo -n apt-get update -qq
sudo -n apt-get install -y -qq google-cloud-cli

log "Done: $(gcloud --version | head -1)"
