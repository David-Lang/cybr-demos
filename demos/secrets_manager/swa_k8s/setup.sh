#!/bin/bash
set -euo pipefail

rc=0
trap 'rc=$?; echo "[ERROR] line $LINENO: command failed: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
compute_init_path="$CYBR_DEMOS_PATH/compute_init/ubuntu"
script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

echo "[INFO] CYBR_DEMOS_PATH=$CYBR_DEMOS_PATH"
echo "[INFO] demo_path=$demo_path"

if [[ ! -d "$demo_path" ]]; then
  echo "[ERROR] demo_path does not exist: $demo_path" >&2
  exit 1
fi

req=(
  "$compute_init_path/install_docker.sh"
  "$compute_init_path/install_terraform.sh"
  "$demo_path/setup/k8s/init_k8s.sh"
  "$demo_path/setup/vault/setup.sh"
  "$demo_path/setup/sm/setup_swa_auth.sh"
  "$demo_path/setup/swa/setup.sh"
  "$demo_path/setup/k8s/build_giftapp_images.sh"
  "$demo_path/setup/k8s/setup.sh"
)
for f in "${req[@]}"; do
  [[ -f "$f" ]] || { echo "[ERROR] missing file: $f" >&2; exit 1; }
done

chmod +x "${req[@]}" || true

if [[ -d /var/lib/rancher/rke2/bin ]]; then
  export PATH="/var/lib/rancher/rke2/bin:$PATH"
fi

install_from_compute_init() {
  local tool="$1"
  local installer="$2"

  if command -v "$tool" >/dev/null 2>&1; then
    echo "[INFO] required tool present: $tool ($(command -v "$tool"))"
    return
  fi

  echo "[INFO] required tool missing: $tool"
  echo "[INFO] installing $tool with $installer"
  bash "$installer"

  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] $tool install completed but $tool is still not on PATH" >&2
    exit 1
  fi
}

ensure_prerequisites() {
  install_from_compute_init "terraform" "$compute_init_path/install_terraform.sh"
  install_from_compute_init "docker" "$compute_init_path/install_docker.sh"

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker >/dev/null 2>&1 || true
  fi

  if docker info >/dev/null 2>&1; then
    return
  fi

  if [[ "${SWA_SETUP_DOCKER_GROUP_REEXEC:-}" != "1" ]] && command -v sg >/dev/null 2>&1 && sg docker -c "docker info >/dev/null 2>&1"; then
    echo "[INFO] restarting setup with docker group membership active"
    exec sg docker -c "export CYBR_DEMOS_PATH='$CYBR_DEMOS_PATH'; export SWA_SETUP_DOCKER_GROUP_REEXEC=1; bash '$script_path'"
  fi

  echo "[ERROR] docker is installed but is not usable by this shell" >&2
  echo "[ERROR] open a new login session or confirm the ubuntu user can access the Docker daemon" >&2
  exit 1
}

run_step() {
  local dir="$1"
  local cmd="$2"
  echo
  echo "[INFO] step: (cd $dir && bash $cmd)"
  ( cd "$dir" && bash -euo pipefail "$cmd" )
}

ensure_prerequisites

# Discover K8s OIDC metadata (writes K8S_PUBLIC_KEYS into vars.env)
run_step "$demo_path/setup/k8s" "./init_k8s.sh"

# Verify cluster connectivity
if command -v kubectl >/dev/null 2>&1; then
  kubectl get nodes || echo "[WARN] kubectl get nodes failed"
fi

# Create PAM safe and sync secrets to Conjur
run_step "$demo_path/setup/vault" "./setup.sh"

# Register SWA control plane with Terraform and install SWA Server + Agent with Helm
run_step "$demo_path/setup/swa" "./setup.sh"

# Configure Conjur JWT authenticator for giftapp-swa JWT-SVIDs
run_step "$demo_path/setup/sm" "./setup_swa_auth.sh"

# Build local GiftApp images when no external registry is supplied
if [[ -z "${GIFTAPP_REGISTRY:-}" ]]; then
  run_step "$demo_path/setup/k8s" "./build_giftapp_images.sh"
fi

# Deploy giftapp-hardcoded and giftapp-swa
run_step "$demo_path/setup/k8s" "./setup.sh"

echo
echo "[INFO] done — run 'bash demo.sh' to explore"
