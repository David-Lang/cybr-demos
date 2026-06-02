#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if command -v curl >/dev/null 2>&1; then
  echo "curl is already installed"
  exit 0
fi

sudo apt-get update
sudo apt-get install -y curl
