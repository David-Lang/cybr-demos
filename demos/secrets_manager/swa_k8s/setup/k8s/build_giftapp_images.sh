#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
src_dir="$demo_path/setup/k8s/giftapp"
out_dir="$demo_path/setup/k8s/.artifacts"
image_tag="${GIFTAPP_IMAGE_TAG:-latest}"
registry="${GIFTAPP_REGISTRY:-localhost}"
ctr_bin="${RKE2_CTR_BIN:-/var/lib/rancher/rke2/bin/ctr}"
containerd_socket="${RKE2_CONTAINERD_SOCKET:-/run/k3s/containerd/containerd.sock}"

mkdir -p "$out_dir"

if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] docker is required to build local GiftApp images" >&2
  exit 1
fi

if [[ ! -x "$ctr_bin" ]]; then
  echo "[ERROR] ctr not found or not executable: $ctr_bin" >&2
  exit 1
fi

build_and_import() {
  local name="$1"
  local dockerfile="$2"
  local image="${registry%/}/${name}:${image_tag}"
  local tar_path="$out_dir/${name}-${image_tag}.tar"

  echo "[INFO] building $image"
  docker build -f "$src_dir/$dockerfile" -t "$image" "$src_dir"

  echo "[INFO] saving $image to $tar_path"
  docker save "$image" -o "$tar_path"

  echo "[INFO] importing $image into RKE2 containerd"
  sudo "$ctr_bin" --address "$containerd_socket" -n k8s.io images import "$tar_path"
}

build_and_import giftapp-hardcoded Dockerfile.hardcoded
build_and_import giftapp-swa Dockerfile.swa

env_file="$demo_path/setup/k8s/giftapp_images.env"
{
  printf 'export GIFTAPP_REGISTRY=%q\n' "$registry"
  printf 'export GIFTAPP_IMAGE_TAG=%q\n' "$image_tag"
} > "$env_file"

echo "[INFO] wrote $env_file"
