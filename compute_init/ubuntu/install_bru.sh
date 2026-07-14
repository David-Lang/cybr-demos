#!/bin/bash
set -euo pipefail

# Bruno CLI (@usebruno/cli) is distributed via npm and requires Node.js.
# Install Node 20 (NodeSource) if npm is not already present, then the CLI.

if command -v bru >/dev/null 2>&1; then
  echo "bru is already installed: $(bru --version 2>/dev/null || true)"
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "Installing Node.js (npm not found)"
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

sudo npm install -g @usebruno/cli

# Verify
command -v bru
bru --version
