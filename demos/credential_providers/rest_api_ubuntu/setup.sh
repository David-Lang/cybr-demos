#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/credential_providers/rest_api_ubuntu"

cd "$demo_path"
./setup/setup.sh
