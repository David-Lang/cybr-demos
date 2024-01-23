#!/bin/bash
set -euo pipefail

# Set CYBR_DEMOS_PATH and persist it in .profile
export CYBR_DEMOS_PATH=$HOME/cybr-demos/demos/
echo "export CYBR_DEMOS_PATH=$HOME/cybr-demos/demos/" >> /"$HOME"/.profile

sudo -i -u ubuntu bash ./install_jq.sh
sudo -i -u ubuntu bash ./install_tree.sh
