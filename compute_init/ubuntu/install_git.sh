#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if command -v git >/dev/null 2>&1; then
  echo "git is already installed"
  exit 0
fi

sudo apt-get update
sudo apt-get install -y git
