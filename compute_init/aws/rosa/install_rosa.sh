#!/bin/bash
set -euo pipefail

# Install the ROSA CLI (Red Hat OpenShift Service on AWS).

if command -v rosa >/dev/null 2>&1; then
  echo "rosa already installed: $(rosa version 2>/dev/null | head -n1 || true)"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

url="https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz"
echo "[INFO] Downloading rosa from $url"
curl -fsSL "$url" -o "$tmp_dir/rosa.tar.gz"
tar -xzf "$tmp_dir/rosa.tar.gz" -C "$tmp_dir"

sudo install -o root -g root -m 0755 "$tmp_dir/rosa" /usr/local/bin/rosa

rosa version 2>/dev/null | head -n1 || true
