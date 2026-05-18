#!/bin/bash
# shellcheck disable=SC2005
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

main() {
  set_variables

  printf "\n\nplatform_auth %s %s [redacted]\n" "$isp_id" "$client_id"
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  printf "\n\nidentity_token acquired (redacted)\n"

  printf "\n\nconjur_isp_auth $isp_subdomain identity_token\n"
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
  printf "\n\nconjur_token acquired (redacted)\n"

  # Setup Auth Service
  printf "\n\napply_conjur_policies $isp_subdomain conjur_token branch policy\n"

  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat authenticator_consumers.yaml)"
  apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat jwt_service_github.yaml)"

  printf "\n\napply_conjur_secret $isp_subdomain conjur_token id value\n"

  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github_jwks_uri_id" "$github_jwks_uri_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github_token_app_property_id" "$github_token_app_property_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github_identity_path_id" "$github_identity_path_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github_issuer_id" "$github_issuer_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$github_enforced_claims_id" "$github_enforced_claims_value"

  printf "\n\nactivate_conjur_service $isp_subdomain conjur_token service_id\n"
  activate_conjur_service "$isp_subdomain" "$conjur_token" "authn-jwt/github"

  # Setup Workloads (host under data/github-apps) then grant apps role for JWT authn
  printf "\n\nresolve_template workload1.tmpl.yaml workload1.yaml\n"
  resolve_template "workload1.tmpl.yaml" "workload1.yaml"

  printf "\n\napply_conjur_policies $isp_subdomain conjur_token branch policy\n"

  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat workload1.yaml)"

  printf "\n\nresolve_template github_apps_vault_grant.tmpl.yaml github_apps_vault_grant.yaml\n"
  resolve_template "github_apps_vault_grant.tmpl.yaml" "github_apps_vault_grant.yaml"

  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat github_apps_vault_grant.yaml)"

  printf "\n\nresolve_template github_jwt_apps_grant.tmpl.yaml github_jwt_apps_grant.yaml\n"
  resolve_template "github_jwt_apps_grant.tmpl.yaml" "github_jwt_apps_grant.yaml"

  apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt/github" "$(cat github_jwt_apps_grant.yaml)"

  printf "\n"
}

# shellcheck disable=SC2153
set_variables() {
  printf "\n\nSetting local vars from Env\n"
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET
  github_repository=$GITHUB_REPOSITORY
  github_workflow=$GITHUB_WORKFLOW

  if [ -z "$github_repository" ] || [ -z "$github_workflow" ]; then
    printf "GITHUB_REPOSITORY and GITHUB_WORKFLOW must be set in setup/vars.env (OIDC workflow + repository claims).\n" >&2
    exit 1
  fi

  github_jwks_uri_id="conjur/authn-jwt/github/jwks-uri"
  github_jwks_uri_value="https://token.actions.githubusercontent.com/.well-known/jwks"

  github_issuer_id="conjur/authn-jwt/github/issuer"
  github_issuer_value="https://token.actions.githubusercontent.com"

  github_token_app_property_id="conjur/authn-jwt/github/token-app-property"
  github_token_app_property_value="workflow"

  github_identity_path_id="conjur/authn-jwt/github/identity-path"
  github_identity_path_value="data/github-apps"

  github_enforced_claims_id="conjur/authn-jwt/github/enforced-claims"
  github_enforced_claims_value="workflow,repository"
}

main "$@"
