#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log(){ echo "[INFO] $*"; }

if ! sudo -n true 2>/dev/null; then
  echo "[ERROR] sudo requires a password (would prompt). Configure passwordless sudo or run as root." >&2
  exit 1
fi

if command -v az >/dev/null 2>&1; then
  log "Azure CLI already installed: $(az version --query '"azure-cli"' -o tsv 2>/dev/null || az --version | head -1)"
  exit 0
fi

log "Installing Azure CLI"

sudo -n apt-get update -qq
sudo -n apt-get install -y -qq ca-certificates curl apt-transport-https lsb-release gnupg

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor \
  | sudo -n tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

AZ_REPO="$(lsb_release -cs)"
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" \
  | sudo -n tee /etc/apt/sources.list.d/azure-cli.list

sudo -n apt-get update -qq
sudo -n apt-get install -y -qq azure-cli

log "Done: $(az version --query '"azure-cli"' -o tsv)"
