#!/bin/bash
set -euo pipefail

rc=0
trap 'rc=$?; echo "[ERROR] line $LINENO: command failed: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"

echo "[INFO] CYBR_DEMOS_PATH=$CYBR_DEMOS_PATH"
echo "[INFO] demo_path=$demo_path"

if [[ ! -d "$demo_path" ]]; then
  echo "[ERROR] demo_path does not exist: $demo_path" >&2
  exit 1
fi

req=(
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

run_step() {
  local dir="$1"
  local cmd="$2"
  echo
  echo "[INFO] step: (cd $dir && bash $cmd)"
  ( cd "$dir" && bash -euo pipefail "$cmd" )
}

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
