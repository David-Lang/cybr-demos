#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$DEMO_DIR/../../.." && pwd)}"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$DEMO_DIR/setup/vars.env"
set +a

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  IMAGE_ARCH="amd64" ;;
  aarch64) IMAGE_ARCH="arm64v8" ;;
  *)       echo "ERROR: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

IMAGE_TAG="${SWA_IMAGE_VERSION}-${IMAGE_ARCH}"
S3_BASE="${SWA_CONTAINER_IMAGES_S3%/}"
if [[ -n "${SWA_IMAGE_CACHE_DIR:-}" ]]; then
  IMAGE_DIR="$SWA_IMAGE_CACHE_DIR"
elif [[ -n "${SWA_RELEASE_S3:-}" ]]; then
  IMAGE_DIR="/tmp/${SWA_RELEASE_S3##*/}/container-images"
else
  IMAGE_DIR="/tmp/swa-container-images"
fi

mkdir -p "$IMAGE_DIR"

download_image() {
  local name="$1"
  local tar_name="${name}-${IMAGE_TAG}.tar"
  local dest="${IMAGE_DIR}/${tar_name}"

  if [[ ! -f "$dest" ]]; then
    echo "[INFO] downloading ${tar_name} from ${S3_BASE}" >&2
    aws s3 cp --no-progress "${S3_BASE}/${tar_name}" "$dest" >&2
  else
    echo "[INFO] image tar already exists: $dest" >&2
  fi

  echo "$dest"
}

import_image() {
  local tar_path="$1"

  if [[ -x /var/lib/rancher/rke2/bin/ctr ]]; then
    echo "[INFO] importing $(basename "$tar_path") into RKE2 containerd"
    sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock -n k8s.io images import "$tar_path"
  elif command -v ctr >/dev/null 2>&1; then
    echo "[INFO] importing $(basename "$tar_path") into containerd"
    sudo ctr -n k8s.io images import "$tar_path"
  else
    echo "[WARN] ctr not found; skipping containerd import"
  fi

  if command -v docker >/dev/null 2>&1; then
    echo "[INFO] loading $(basename "$tar_path") into Docker"
    docker image load --input "$tar_path" >/dev/null || echo "[WARN] docker load failed; continuing because RKE2 import is the required path"
  fi
}

agent_tar=$(download_image "swa-agent")
server_tar=$(download_image "swa-server")

import_image "$agent_tar"
import_image "$server_tar"

cat > "$SCRIPT_DIR/swa_images.env" <<EOF
# Runtime file for imported SWA image settings
export SWA_IMAGE_TAG="${IMAGE_TAG}"
export SWA_AGENT_IMAGE_REPOSITORY="swa-agent"
export SWA_SERVER_IMAGE_REPOSITORY="swa-server"
EOF

echo "[INFO] wrote $SCRIPT_DIR/swa_images.env"
