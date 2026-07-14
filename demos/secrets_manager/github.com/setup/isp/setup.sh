#!/bin/bash
# shellcheck disable=SC2059
# Ensures the service account is a member of the Conjur Cloud Admin role so it can
# obtain a Conjur session token and manage authenticators/workloads/policy.
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

# CyberArk Identity role name for the Secrets Manager (Conjur Cloud) admin role.
CONJUR_ADMIN_ROLE="${CONJUR_ADMIN_ROLE:-ID_SecretManagerConjurCloudAdmin}"
# How long to wait for Conjur Cloud to sync the new role membership.
CONJUR_ROLE_WAIT_ATTEMPTS="${CONJUR_ROLE_WAIT_ATTEMPTS:-30}"

main() {
  set_variables

  printf "\n\nEnsuring service user is a member of %s\n" "$CONJUR_ADMIN_ROLE"

  local identity_token service_user_id
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  service_user_id=$(get_service_user_id "$isp_id" "$identity_token")
  printf "service_user_id: %s\n" "$service_user_id"

  add_user_to_role "$isp_id" "$identity_token" "$CONJUR_ADMIN_ROLE" "$service_user_id"
  printf "Added service user to %s\n" "$CONJUR_ADMIN_ROLE"

  # Conjur Cloud syncs ISP role membership on an interval. Wait until the service
  # user can actually obtain a Conjur session token so later stages don't spin on
  # an empty token.
  printf "Waiting for Conjur to recognize the admin role"
  local attempts=0 conjur_token=""
  while [ "$attempts" -lt "$CONJUR_ROLE_WAIT_ATTEMPTS" ]; do
    # Refresh the identity token so it reflects current role membership.
    identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
    conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
    if [ "${#conjur_token}" -gt 100 ]; then
      printf " ready\n"
      return 0
    fi
    printf "."
    sleep 10
    attempts=$((attempts + 1))
  done

  printf "\nERROR: Conjur did not recognize the admin role within the timeout.\n" >&2
  exit 1
}

# shellcheck disable=SC2153
set_variables() {
  isp_id="$TENANT_ID"
  isp_subdomain="$TENANT_SUBDOMAIN"
  client_id="$CLIENT_ID"
  client_secret="$CLIENT_SECRET"
}

main "$@"
