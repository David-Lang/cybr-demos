#!/bin/bash
set -euo pipefail

# Set CYBR_DEMOS_PATH and persist it in .profile
export CYBR_DEMOS_PATH=$HOME/cybr-demos
echo "export CYBR_DEMOS_PATH=$HOME/cybr-demos" >> "$HOME/.profile"

sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_jq.sh
sudo -i -u ubuntu bash "$CYBR_DEMOS_PATH"/compute_init/ubuntu/install_tree.sh

