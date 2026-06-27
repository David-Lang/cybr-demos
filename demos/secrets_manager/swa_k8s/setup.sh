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

# ── Cloud provider flags ──────────────────────────────────────────────────────
# Inherit from env (survives docker-group re-exec) then override from CLI args.
SETUP_AWS="${SETUP_AWS:-false}"
SETUP_AZURE="${SETUP_AZURE:-false}"
SETUP_GCP="${SETUP_GCP:-false}"

for _arg in "$@"; do
  case "$_arg" in
    --aws)   SETUP_AWS=true ;;
    --azure) SETUP_AZURE=true ;;
    --gcp)   SETUP_GCP=true ;;
    *) echo "[ERROR] unknown option: $_arg  (valid: --aws --azure --gcp)" >&2; exit 1 ;;
  esac
done
export SETUP_AWS SETUP_AZURE SETUP_GCP

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
    exec sg docker -c "export CYBR_DEMOS_PATH='$CYBR_DEMOS_PATH' SETUP_AWS='$SETUP_AWS' SETUP_AZURE='$SETUP_AZURE' SETUP_GCP='$SETUP_GCP' SWA_SETUP_DOCKER_GROUP_REEXEC=1; bash '$script_path'"
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

# ── Optional cloud provider setups ───────────────────────────────────────────
cloud_path="$demo_path/setup/cloud"

if [[ "$SETUP_AWS" == "true" || "$SETUP_AZURE" == "true" || "$SETUP_GCP" == "true" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
  # shellcheck disable=SC1091
  source "$cloud_path/vars.env"
  set +a

  run_cloud_step() {
    local cloud="$1"
    local dir="$cloud_path/$cloud"
    local creds_file="$cloud_path/${cloud}_credentials.env"

    if [[ ! -f "$creds_file" ]]; then
      echo "[ERROR] Credentials file not found: $creds_file" >&2
      echo "[ERROR] Create this file and add your ${cloud^^} credentials" >&2
      exit 1
    fi

    echo
    echo "[INFO] step: $cloud cloud setup"
    (
      cd "$dir"
      set -a
      # shellcheck disable=SC1090
      source "$creds_file"
      set +a
      bash -euo pipefail "./setup.sh"
    )
  }

  if [[ "$SETUP_AWS" == "true" ]]; then
    install_from_compute_init "aws" "$compute_init_path/install_awscli.sh"
    run_cloud_step "aws"
  fi

  if [[ "$SETUP_AZURE" == "true" ]]; then
    install_from_compute_init "az" "$compute_init_path/install_azurecli.sh"
    run_cloud_step "azure"
  fi

  if [[ "$SETUP_GCP" == "true" ]]; then
    install_from_compute_init "gcloud" "$compute_init_path/install_gcpcli.sh"
    run_cloud_step "gcp"
  fi
fi

echo
echo "[INFO] done — run 'bash demo.sh' to explore"
