#!/bin/bash
set -euo pipefail

if command -v minikube >/dev/null 2>&1; then
  echo "minikube already installed: $(minikube version | head -1)"
  exit 0
fi

echo "Installing minikube..."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
esac

curl -fsSL -o "$tmp_dir/minikube" "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}"
sudo install -o root -g root -m 0755 "$tmp_dir/minikube" /usr/local/bin/minikube

minikube version | head -1
