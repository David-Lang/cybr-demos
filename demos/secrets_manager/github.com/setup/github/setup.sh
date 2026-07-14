#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

main() {
  set_variables

  # 1. Render the CONJUR_* handoff values from the demo state.
  printf "\n\nresolve_template settings_variables.tmpl.env settings_variables.env\n"
  resolve_template "settings_variables.tmpl.env" "settings_variables.env"

  # 2. Load CONJUR_* and map to the SM_* names the workflows consume.
  set -a
  # shellcheck disable=SC1091
  source "./settings_variables.env"
  set +a

  export SM_URL="$CONJUR_URL"
  export SM_ACCOUNT="$CONJUR_ACCOUNT"
  export SM_JWT_AUTHN_ID="$CONJUR_JWT_AUTHN_ID"
  export SM_SECRET_ID_1="$CONJUR_SECRET_ID_1"
  export SM_SECRET_ID_2="$CONJUR_SECRET_ID_2"

  # 3. Provision the api-key credential. The workload host created by the conjur
  #    setup is annotated authn/api-key: true, so we rotate its key here and push
  #    it straight to GitHub (never written to disk).
  local workload_id="data/workloads/github-actor/${JWT_CLAIM_IDENTITY}"
  printf "\n\nProvisioning api-key credential for host/%s\n" "$workload_id"
  local identity_token conjur_token api_key
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
  api_key=$(rotate_workload_api_key "$isp_subdomain" "$conjur_token" "$workload_id")
  [ -n "$api_key" ] || { printf "ERROR: api-key rotation returned empty for host/%s\n" "$workload_id" >&2; exit 1; }
  export SM_USERNAME="host/${workload_id}"
  export SM_API_KEY="$api_key"

  # 4. Terraform (JWT auth) values. Blank overrides are derived from the SM_* set.
  export TFVAR_APPLIANCE_URL="${TFVAR_APPLIANCE_URL:-$SM_URL}"
  export TFVAR_ACCOUNT="${TFVAR_ACCOUNT:-$SM_ACCOUNT}"
  export TFVAR_sm_secret_id_1="${TFVAR_sm_secret_id_1:-$SM_SECRET_ID_1}"
  export TFVAR_SSL_CERT="${TFVAR_SSL_CERT:-}"

  # init-gh-vars-secrets.sh reads environment-scoped values as ENVNAME__KEY.
  export TERRAFORM__SM_URL="$SM_URL"
  export TERRAFORM__SM_ACCOUNT="$SM_ACCOUNT"
  export TERRAFORM__SM_JWT_AUTHN_ID="$SM_JWT_AUTHN_ID"
  export TERRAFORM__SM_SECRET_ID_1="$SM_SECRET_ID_1"
  export TERRAFORM__SM_SECRET_ID_2="$SM_SECRET_ID_2"
  export TERRAFORM__TFVAR_APPLIANCE_URL="$TFVAR_APPLIANCE_URL"
  export TERRAFORM__TFVAR_ACCOUNT="$TFVAR_ACCOUNT"
  export TERRAFORM__TFVAR_SSL_CERT="$TFVAR_SSL_CERT"
  export TERRAFORM__TFVAR_sm_secret_id_1="$TFVAR_sm_secret_id_1"

  # 5. Populate the GitHub repository (variables, secrets, environments).
  local env_args=()
  local e
  for e in ${GH_ENVIRONMENTS:-dev staging main terraform}; do
    env_args+=(--env "$e")
  done

  printf "\n\nPopulating GitHub repo %s (envs: %s)\n" "$GH_REPO" "${GH_ENVIRONMENTS:-dev staging main terraform}"
  ./init-gh-vars-secrets.sh --repo "$GH_REPO" "${env_args[@]}" --non-interactive
}

# shellcheck disable=SC2153
# shellcheck disable=SC2034
set_variables() {
  printf "\nSetting local vars from Env"

  isp_id="$TENANT_ID"
  isp_subdomain="$TENANT_SUBDOMAIN"
  client_id="$CLIENT_ID"
  client_secret="$CLIENT_SECRET"
  safe_name="$SAFE_NAME"

  : "${JWT_CLAIM_IDENTITY:?JWT_CLAIM_IDENTITY must be set (GitHub actor value)}"
  : "${GH_REPO:?GH_REPO must be set (owner/repo)}"
}

main "$@"
