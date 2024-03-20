#!/bin/bash
# shellcheck disable=SC2005
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/isp_vars.env.sh"

main() {
  set_variables

  printf "\n\nplatform_auth $isp_id $client_id $client_secret\n"
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  printf "\n\nidentity_token: \n$identity_token\n"

  printf "\n\nconjur_isp_auth $isp_subdomain identity_token\n"
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
  printf "\n\nconjur_token: \n$conjur_token\n"

  # Setup Auth Service
  printf "\n\napply_conjur_policies $isp_subdomain conjur_token branch policy\n"

  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat authenticator_consumers.yaml)"
  apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat jwt_service_github1.yaml)"

  printf "\n\napply_conjur_secret $isp_subdomain conjur_token id value\n"

  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github1_jwks_uri_id" "$github1_jwks_uri_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github1_token_app_property_id" "$github1_token_app_property_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github1_identity_path_id" "$github1_identity_path_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github1_issuer_id" "$github1_issuer_value"

  printf "\n\nactivate_conjur_service $isp_subdomain conjur_token service_id\n"
  activate_conjur_service "$isp_subdomain" "$conjur_token" "authn-jwt/github1"

  # Setup Workloads

  printf "\n\nresolve_template "workload1.tmpl.yaml" "workload1.yaml\n"
  resolve_template "workload1.tmpl.yaml" "workload1.yaml"

  printf "\n\napply_conjur_policies $isp_subdomain conjur_token branch policy\n"

  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat workload1.yaml)"

  printf "\n"
}

# shellcheck disable=SC2153
set_variables() {
  printf "\n\nSetting local vars from Env\n"
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET

  github1_jwks_uri_id="conjur/authn-jwt/github1/jwks-uri"
  github1_jwks_uri_value="https://token.actions.githubusercontent.com/.well-known/jwks"

  github1_issuer_id="conjur/authn-jwt/github1/issuer"
  github1_issuer_value="https://token.actions.githubusercontent.com"

  github1_token_app_property_id="conjur/authn-jwt/github1/token-app-property"
  github1_token_app_property_value="actor"

  github1_identity_path_id="conjur/authn-jwt/github1/identity-path"
  github1_identity_path_value="data/workloads/github-actor"
}


main "$@"
