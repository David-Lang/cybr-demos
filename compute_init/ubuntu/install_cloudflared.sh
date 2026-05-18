#!/bin/bash
set -euo pipefail

if command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared already installed: $(cloudflared --version 2>&1 | head -1)"
  exit 0
fi

echo "Installing cloudflared..."

# Cloudflare publishes apt packages for Ubuntu/Debian.
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

distro_codename="$(lsb_release -cs 2>/dev/null || echo jammy)"
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared ${distro_codename} main" \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

sudo apt-get update
sudo apt-get install -y cloudflared

cloudflared --version 2>&1 | head -1
