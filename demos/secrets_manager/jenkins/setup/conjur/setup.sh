#!/bin/bash
# shellcheck disable=SC2005
# shellcheck disable=SC2059
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/jenkins"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"
jenkins_env="$demo_path/setup/.jenkins.env"

if [ -f "$jenkins_env" ]; then
  # shellcheck disable=SC1091
  source "$jenkins_env"
fi

main() {
  set_variables

  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")

  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat authenticator_consumers.yaml)"

  # Renders the authenticator policy with CONJUR_JWT_AUTHN_ID baked in.
  # Declares variables for jwks-uri, public-keys, issuer, audience, etc.
  resolve_template "jwt_service_jenkins.tmpl.yaml" "jwt_service_jenkins.yaml"
  apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt" "$(cat jwt_service_jenkins.yaml)"

  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$jenkins_jwks_uri_id" "$jenkins_jwks_uri_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$jenkins_token_app_property_id" "$jenkins_token_app_property_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$jenkins_identity_path_id" "$jenkins_identity_path_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$jenkins_issuer_id" "$jenkins_issuer_value"
  apply_conjur_secret "$isp_subdomain" "$conjur_token" "$jenkins_audience_id" "$jenkins_audience_value"

  activate_conjur_service "$isp_subdomain" "$conjur_token" "authn-jwt/${CONJUR_JWT_AUTHN_ID}"

  resolve_template "workload1.tmpl.yaml" "workload1.yaml"
  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat workload1.yaml)"

  resolve_template "jenkins_apps_vault_grant.tmpl.yaml" "jenkins_apps_vault_grant.yaml"
  apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$(cat jenkins_apps_vault_grant.yaml)"

  resolve_template "jenkins_jwt_apps_grant.tmpl.yaml" "jenkins_jwt_apps_grant.yaml"
  apply_conjur_policy "$isp_subdomain" "$conjur_token" "conjur/authn-jwt/${CONJUR_JWT_AUTHN_ID}" "$(cat jenkins_jwt_apps_grant.yaml)"

  render_pipeline_groovy

  printf "\nConjur setup complete.\n"
  printf "  Authenticator: authn-jwt/%s\n" "$CONJUR_JWT_AUTHN_ID"
  printf "  Workload host: data/jenkins-apps/%s\n" "$JWT_CLAIM_IDENTITY"
  printf "  JWKS URI:      %s\n" "$jenkins_jwks_uri_value"
  printf "\n"
}

set_variables() {
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET

  if [ -z "${JWT_CLAIM_IDENTITY:-}" ]; then
    printf "JWT_CLAIM_IDENTITY must be set in setup/vars.env\n" >&2
    exit 1
  fi

  if [ -z "${JENKINS_JWKS_URI:-}" ] || [ -z "${JENKINS_ISSUER:-}" ]; then
    printf "JENKINS_JWKS_URI and JENKINS_ISSUER must be set (run setup/jenkins/setup.sh first).\n" >&2
    exit 1
  fi

  authn_id="${CONJUR_JWT_AUTHN_ID:-jenkins1}"
  audience="${CONJUR_AUDIENCE:-cyberark-conjur}"

  jenkins_jwks_uri_id="conjur/authn-jwt/${authn_id}/jwks-uri"
  jenkins_jwks_uri_value="$JENKINS_JWKS_URI"

  jenkins_issuer_id="conjur/authn-jwt/${authn_id}/issuer"
  jenkins_issuer_value="$JENKINS_ISSUER"

  jenkins_token_app_property_id="conjur/authn-jwt/${authn_id}/token-app-property"
  jenkins_token_app_property_value="jenkins_full_name"

  jenkins_identity_path_id="conjur/authn-jwt/${authn_id}/identity-path"
  jenkins_identity_path_value="data/jenkins-apps"

  jenkins_audience_id="conjur/authn-jwt/${authn_id}/audience"
  jenkins_audience_value="$audience"
}

render_pipeline_groovy() {
  bash "$demo_path/render_pipeline.sh"
}

main "$@"
