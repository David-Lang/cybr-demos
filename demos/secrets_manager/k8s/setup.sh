#!/bin/bash
set -euo pipefail

# Print failing command + line number
rc=0
trap 'rc=$?; echo "[ERROR] line $LINENO: command failed: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

# Require CYBR_DEMOS_PATH (or provide a default)
#: "${CYBR_DEMOS_PATH:=/opt/cybr-demos}"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/k8s"

echo "[INFO] CYBR_DEMOS_PATH=$CYBR_DEMOS_PATH"
echo "[INFO] demo_path=$demo_path"
echo "[INFO] user=$(whoami) home=$HOME"
echo "[INFO] pwd=$(pwd)"

# Basic sanity checks
if [[ ! -d "$demo_path" ]]; then
  echo "[ERROR] demo_path does not exist: $demo_path" >&2
  echo "[HINT] Is the repo cloned there? Are you running as the same user that owns it?" >&2
  exit 1
fi

# Ensure scripts exist
req=(
  "$demo_path/setup/k8s/init_rancher.sh"
  "$demo_path/setup/vault/setup.sh"
  "$demo_path/setup/sm/setup.sh"
  "$demo_path/setup/k8s/setup.sh"
)
for f in "${req[@]}"; do
  [[ -f "$f" ]] || { echo "[ERROR] missing file: $f" >&2; exit 1; }
done

if [[ -f "$demo_path/check_prereqs.sh" ]] && [[ "${SKIP_K8S_PREREQ_CHECK:-}" != "1" ]]; then
  echo "[INFO] Running $demo_path/check_prereqs.sh (set SKIP_K8S_PREREQ_CHECK=1 to skip)"
  bash "$demo_path/check_prereqs.sh" || {
    echo "[ERROR] Prerequisite check failed. Fix the issues above, then re-run ./setup.sh" >&2
    exit 1
  }
fi

# Optional: ensure executable (won't hurt if already)
chmod +x \
  "$demo_path/check_prereqs.sh" \
  "$demo_path/setup/k8s/init_rancher.sh" \
  "$demo_path/setup/vault/setup.sh" \
  "$demo_path/setup/sm/setup.sh" \
  "$demo_path/setup/k8s/setup.sh" \
  || true

# If you're using RKE2/Rancher kubectl path, make it explicit (adjust if needed)
if [[ -d /var/lib/rancher/rke2/bin ]]; then
  export PATH="/var/lib/rancher/rke2/bin:$PATH"
fi

# If kubeconfig should exist from init_rancher, you can pre-set this if you know it
# export KUBECONFIG="$HOME/.kube/config"

echo "[INFO] kubectl=$(command -v kubectl || echo 'not found')"
if command -v kubectl >/dev/null 2>&1; then
  kubectl version --client --short 2>/dev/null || true
fi

run_step() {
  local dir="$1"
  local cmd="$2"
  echo
  echo "[INFO] step: (cd $dir && $cmd)"
  ( cd "$dir" && bash -x -e "$cmd" )
}

# Init K8s metadata
run_step "$demo_path/setup/k8s" "./init_rancher.sh"

# Quick check: do we have a cluster context?
if command -v kubectl >/dev/null 2>&1; then
  echo "[INFO] kubectl cluster check"
  kubectl get nodes || echo "[WARN] kubectl get nodes failed (context/kubeconfig?)"
fi

# Setup Vault
run_step "$demo_path/setup/vault" "./setup.sh"

# Setup Secrets Manager
run_step "$demo_path/setup/sm" "./setup.sh"

# Setup K8s
run_step "$demo_path/setup/k8s" "./setup.sh"

echo "[INFO] done"
