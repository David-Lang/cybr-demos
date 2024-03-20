#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/isp_vars.env.sh"

main() {
  set_variables

  printf "\n\nresolve_template workload1.tmpl.yaml workload1.yaml\n"
  resolve_template "settings_variables.tmpl.env" "settings_variables.env"

  printf "\n\nIn the github repo to be used configure these variables:\n"
  cat settings_variables.env
}

# shellcheck disable=SC2153
# shellcheck disable=SC2034
set_variables() {
  printf "\nSetting local vars from Env"

  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  safe_name=$SAFE_NAME
}

main "$@"
