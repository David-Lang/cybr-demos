#!/bin/bash
set -euo pipefail

# Set CYBR_DEMOS_PATH and persist it in .profile
export CYBR_DEMOS_PATH=$HOME/cybr-demos
echo "export CYBR_DEMOS_PATH=$HOME/cybr-demos" >> "$HOME/.profile"

settings_dir="$HOME/.cybr-demos"

if [ -d "$settings_dir" ]; then
  echo "$settings_dir exists. Skipping compute setup"
  exit 0  # Exit with success
fi

mkdir "$settings_dir"
chmod 700 "$settings_dir"

# Suppress debconf dialog
export DEBIAN_FRONTEND=noninteractive

sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_jq.sh
sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_tree.sh
sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_docker.sh
sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_terraform.sh
sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_awscli.sh
sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_kubectl.sh

#sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_summon.sh

