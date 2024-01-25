#!/bin/bash
# shellcheck disable=SC2005
# shellcheck disable=SC2059
set -euo pipefail

# Doc for Conjur Jenkins plugin:
# https://plugins.jenkins.io/conjur-credentials/

source "$CYBR_DEMOS_PATH/demos/isp_vars.env.sh"

main() {
  printf "\nConjur Setup\n"
  set_variables
  platform_auth "$client_id" "$client_secret"
  conjur_isp_auth

  # Setup Auth Service
  apply_conjur_policy "data" "$(cat policy_service_consumers.yaml)"
  apply_conjur_policy "conjur/authn-jwt" "$(cat policy_service1.yaml)"
  apply_conjur_secret "$jenkins1_jwks_uri_id" "$jenkins1_jwks_uri_value"
  apply_conjur_secret "$jenkins1_token_app_property_id" "$jenkins1_token_app_property_value"
  apply_conjur_secret "$jenkins1_identity_path_id" "$jenkins1_identity_path_value"
  apply_conjur_secret "$jenkins1_issuer_id" "$jenkins1_issuer_value"
  apply_conjur_secret "$jenkins1_audience_id" "$jenkins1_audience_value"

  activate_conjur_service "authn-jwt/jenkins1"

  # Setup Workloads
  resolve_template "workload1.tmpl.yaml" "policy_workload1.yaml"
  apply_conjur_policy "data" "$(cat workload1.yaml)"

  printf "\n"
}

# shellcheck disable=SC2153
set_variables() {
  printf "\nSetting local vars from Env"
  isp_id=$TENANT_ID
  isp_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET
  host_fqdn=$HOST_FQDN
  jenkins_port=$JENKINS_PORT

  jenkins1_jwks_uri_id="conjur/authn-jwt/jenkins1/jwks-uri"
  jenkins1_jwks_uri_value="https://$host_fqdn:$jenkins_port/jwtauth/conjur-jwk-set"

  jenkins1_issuer_id="conjur/authn-jwt/jenkins1/issuer"
  jenkins1_issuer_value="http://$host_fqdn:$jenkins_port"

  jenkins1_token_app_property_id="conjur/authn-jwt/jenkins1/token-app-property"
  jenkins1_token_app_property_value="sub"

  jenkins1_identity_path_id="conjur/authn-jwt/jenkins1/identity-path"
  jenkins1_identity_path_value="data/workloads/jenkins-sub"

  jenkins1_audience_id="conjur/authn-jwt/jenkins1/audience"
  jenkins1_audience_value="demo"
}

platform_auth() {
  # $1 client_id, $2 client_secret
  printf "\nISP Auth client_id: $1\n"
  identity_token=$(curl --silent \
  --location "https://$isp_id.id.cyberark.cloud/oauth2/platformtoken" \
  --header 'X-IDAP-NATIVE-CLIENT: true' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_id=$1" \
  --data-urlencode "client_secret=$2" | jq -r .access_token)
  # echo "identity_token: $identity_token"
}

conjur_isp_auth(){
  printf "\nConjur Auth\n"
  conjur_token=$(curl --silent \
  --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/authn-oidc/cyberark/conjur/authenticate" \
  --header 'Accept-Encoding: base64' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "id_token=$identity_token")
  # echo "conjur_token: $conjur_token"
}

apply_conjur_policy(){
  # $1 branch, $2 policy
  printf "\nApply on Conjur Policy on Branch $1:\n$2\n"
  curl --silent \
  --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/policies/conjur/policy/$1" \
  --header "Authorization: Token token=\"$conjur_token\"" \
  --header 'Content-Type: text/plain' \
  --data "$2"
}

apply_conjur_secret(){
  # $1 id, 2$ value
  printf "\nActivate Conjur Secret ID: $1 Value: $2"
  curl --silent \
  --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/$1" \
  --header "Authorization: Token token=\"$conjur_token\"" \
  --header 'Content-Type: text/plain' \
  --data "$2"
}

activate_conjur_service(){
  # $1 service_id
  printf "\nActivate Conjur Service ID: $1"
  curl --silent \
  --request PATCH --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/$1/conjur" \
  --header 'X-Request-Id: <string>' \
  --header "Authorization: Token token=\"$conjur_token\"" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'enabled=true'
}

resolve_template() {
    # $1 branch, $2 policy
    if [ $# -ne 2 ]; then
        echo "Usage: resolve_template input_file output_file"
        return 1
    fi
    printf "\nResolve Template: input_file $1 output_file: $2\n"
    input_file="$1"
    output_file="$2"
    printf "" > "$output_file"

    while IFS= read -r line; do
        # Use a regular expression to find Go lang style templates with dots
        # echo "$line"
        pattern='\{\{\s*\.([A-Z][A-Z0-9_]*)\s*\}\}'
        while [[ $line =~ $pattern ]]; do
            pattern_match=${BASH_REMATCH[0]}
            echo "Found pattern: $pattern_match"
            template_var=${BASH_REMATCH[1]}
            echo "Variable: $template_var"
            value="${!template_var}"
            echo "Value: $value"
            # Replace the template with the environment variable value
            line="${line//$pattern_match/$value}"
        done
        # Append the modified line to the output file
        echo "$line" >> "$output_file"
    done < "$input_file"
}

main "$@"


