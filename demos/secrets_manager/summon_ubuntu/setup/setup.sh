#!/bin/bash

set -e

echo "Starting Summon installation for Ubuntu..."

# Define installation directory
INSTALL_DIR="/usr/local/bin"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download and install Summon
echo "Downloading Summon..."
curl -sSL https://github.com/cyberark/summon/releases/latest/download/summon-linux-amd64.tar.gz -o summon.tar.gz

echo "Installing Summon..."
tar -xzf summon.tar.gz
sudo mv summon-linux-amd64 "$INSTALL_DIR/summon"
sudo chmod +x "$INSTALL_DIR/summon"

# Download and install Conjur provider
echo "Downloading Conjur provider..."
curl -sSL https://github.com/cyberark/summon-conjur/releases/latest/download/summon-conjur-linux-amd64.tar.gz -o summon-conjur.tar.gz

echo "Installing Conjur provider..."
sudo mkdir -p "$INSTALL_DIR/summon-providers"
tar -xzf summon-conjur.tar.gz
sudo mv summon-conjur-linux-amd64 "$INSTALL_DIR/summon-providers/summon-conjur"
sudo chmod +x "$INSTALL_DIR/summon-providers/summon-conjur"

# Clean up
cd -
rm -rf "$TEMP_DIR"

echo ""
echo "Installation complete!"
echo "Summon: $INSTALL_DIR/summon"
echo "Conjur Provider: $INSTALL_DIR/summon-providers/summon-conjur"
echo ""

# Run configure script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/configure.sh" ]; then
    echo "Running configuration script..."
    bash "$SCRIPT_DIR/configure.sh"
else
    echo "Note: Run './configure.sh' to set up Conjur environment variables"
fi

echo ""
echo "Setup complete! You can now run the demo with: ./demo.sh"
