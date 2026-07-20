#!/bin/bash
set -euo pipefail

# Install the OpenShift CLI (oc). Also drops in kubectl from the same bundle
# only if kubectl is not already present (the ubuntu base setup installs it).

if command -v oc >/dev/null 2>&1; then
  echo "oc already installed: $(oc version --client 2>/dev/null | head -n1 || true)"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
echo "[INFO] Downloading oc from $url"
curl -fsSL "$url" -o "$tmp_dir/oc.tar.gz"
tar -xzf "$tmp_dir/oc.tar.gz" -C "$tmp_dir"

sudo install -o root -g root -m 0755 "$tmp_dir/oc" /usr/local/bin/oc
if ! command -v kubectl >/dev/null 2>&1 && [ -f "$tmp_dir/kubectl" ]; then
  sudo install -o root -g root -m 0755 "$tmp_dir/kubectl" /usr/local/bin/kubectl
fi

oc version --client 2>/dev/null | head -n1 || oc version --client
