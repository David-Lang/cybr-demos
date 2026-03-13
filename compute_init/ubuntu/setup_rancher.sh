#!/bin/bash
set -euo pipefail

export cybr_demos_path="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"

settings_dir="${cybr_demos_path}/settings"
log_file="${settings_dir}/init_log"
sentinel="${settings_dir}/.initialized"

if [[ -f "$sentinel" ]]; then
  echo "Already initialized ($sentinel exists). Skipping setup."
  exit 0
fi

sudo mkdir -p "$settings_dir"
sudo chown ubuntu:ubuntu "$settings_dir"
sudo chmod 775 "$settings_dir"

sudo -u ubuntu -H touch "$log_file"
sudo chmod 664 "$log_file"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$log_file"
}

run_as_root() {
  sudo -H bash -c "$*" >>"$log_file" 2>&1
}

run_as_ubuntu() {
  sudo -u ubuntu -H bash -c "$*" >>"$log_file" 2>&1
}

export DEBIAN_FRONTEND=noninteractive

log "Starting compute + demo initialization..."

# root installers (anything that touches /usr/local, apt, systemd, /etc)
root_scripts=(
  "${cybr_demos_path}/compute_init/ubuntu/install_jq.sh"
  "${cybr_demos_path}/compute_init/ubuntu/install_tree.sh"
  "${cybr_demos_path}/compute_init/ubuntu/install_awscli.sh"
  "${cybr_demos_path}/compute_init/ubuntu/install_kubectl.sh"
  "${cybr_demos_path}/compute_init/ubuntu/install_helm.sh"
  "${cybr_demos_path}/compute_init/ubuntu/install_rancher.sh"
  "${cybr_demos_path}/compute_init/ubuntu/install_k9s.sh"
)

# ubuntu scripts (demo setup, kube interactions, repo config, etc.)
ubuntu_scripts=(
)

for script in "${root_scripts[@]}"; do
  log "Running as root: ${script}"
  if run_as_root "bash '$script'"; then
    log "SUCCESS: $(basename "$script")"
  else
    log "ERROR: $(basename "$script") failed. See ${log_file}"
    exit 1
  fi
done

for script in "${ubuntu_scripts[@]}"; do
  log "Running as ubuntu: ${script}"
  if run_as_ubuntu "bash '$script'"; then
    log "SUCCESS: $(basename "$script")"
  else
    log "ERROR: $(basename "$script") failed. See ${log_file}"
    exit 1
  fi
done

sudo -u ubuntu -H touch "$sentinel"
log "Initialization complete."
