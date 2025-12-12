#!/bin/bash
# shellcheck disable=SC2005
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/isp_vars.env.sh"

main() {
  set_variables

  # Get Secrets Hub Role ARN

  # Setup AWS Cloud Formation Template
  cd terraform
  ./build.sh

  # Set Secrets Hub Secret Store

  # Set Secrets Hub Policy

  printf "\n"
}

# shellcheck disable=SC2153
set_variables() {
  printf "\nSetting local vars from Env\n"

  set -a
  source "../vars.env"
  set +a

}



main "$@"
