#!/bin/bash

set -euo pipefail

echo "Starting Summon installation for Ubuntu..."

INSTALL_DIR="/usr/local/bin"
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Downloading Summon..."
curl -sSL https://github.com/cyberark/summon/releases/latest/download/summon-linux-amd64.tar.gz -o summon.tar.gz

echo "Installing Summon..."
tar -xzf summon.tar.gz
sudo mv summon-linux-amd64 "$INSTALL_DIR/summon"
sudo chmod +x "$INSTALL_DIR/summon"

echo "Downloading Conjur provider..."
curl -sSL https://github.com/cyberark/summon-conjur/releases/latest/download/summon-conjur-linux-amd64.tar.gz -o summon-conjur.tar.gz

echo "Installing Conjur provider..."
sudo mkdir -p "$INSTALL_DIR/summon-providers"
tar -xzf summon-conjur.tar.gz
sudo mv summon-conjur-linux-amd64 "$INSTALL_DIR/summon-providers/summon-conjur"
sudo chmod +x "$INSTALL_DIR/summon-providers/summon-conjur"

cd - >/dev/null
rm -rf "$TEMP_DIR"

echo ""
echo "Installation complete!"
echo "Summon: $INSTALL_DIR/summon"
echo "Conjur Provider: $INSTALL_DIR/summon-providers/summon-conjur"
