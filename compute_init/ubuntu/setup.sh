#!/bin/bash
set -euo pipefail

# 1. Use existing CYBR_DEMOS_PATH or default to /opt/cybr-demos
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"

settings_dir="$CYBR_DEMOS_PATH/settings"
log_file="$settings_dir/init_log"

# Check if already initialized
if [ -d "$settings_dir" ]; then
  echo "$settings_dir exists. Skipping compute setup"
  exit 0
fi

mkdir "$settings_dir"
chmod 777 "$settings_dir"
touch "$log_file"

# Simple logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$log_file"
}

log "Starting compute initialization..."

# Suppress debconf dialog
export DEBIAN_FRONTEND=noninteractive

scripts=(
  "install_jq.sh"
  "install_tree.sh"
  "install_docker.sh"
  "install_terraform.sh"
  "install_awscli.sh"
  "install_kubectl.sh"
  "install_k9s.sh"
  "install_helm.sh"
  "install_minikube.sh"
  "install_cloudflared.sh"
)

# 3. Execute scripts and log output
for script in "${scripts[@]}"; do
  log "Installing: $script"
  # Redirects both stdout and stderr (2>&1) to the log file in append mode (>>)
  # shellcheck disable=SC2024
  if sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH/compute_init/ubuntu/$script" >> "$log_file" 2>&1; then
    log "SUCCESS: $script installed."
  else
    log "ERROR: $script failed. Check $log_file for details."
    exit 1
  fi
done

log "Initialization complete."