#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/credential_providers/ccp_ubuntu"

cd "$demo_path/setup"
./setup.sh
