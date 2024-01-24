#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/demo_utility.sh"

echo "Run the Workflow via github.com"
echo
# shellcheck disable=SC2154
printf "${Url_Blue}https://github.com/tbd_account/tbd_repo/actions/${Color_Off}\n"
echo ""
echo