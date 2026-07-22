#!/bin/bash
# shellcheck disable=SC2059
# Validates the github.com demo after setup: confirms the Secrets Manager server
# side and the GitHub repository configuration are in place.
set -uo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# Sourcing the framework enables `set -e`; disable it so soft checks can continue.
set +e

API="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
FAIL=0
pass() { printf "  [PASS] %s\n" "$*"; }
bad()  { printf "  [FAIL] %s\n" "$*"; FAIL=1; }

list_resources() {
  # $1 kind, $2 conjur_token
  curl --silent --location "$API/resources/conjur?kind=$1" \
    --header "Authorization: Token token=\"$2\""
}

main() {
  : "${SAFE_NAME:?SAFE_NAME must be set}"
  : "${JWT_CLAIM_IDENTITY:?JWT_CLAIM_IDENTITY must be set}"
  : "${GH_REPO:?GH_REPO must be set}"

  local workload="data/workloads/github-repo/${JWT_CLAIM_IDENTITY}"

  printf "\n== Secrets Manager server side ==\n"
  local id_token conjur_token
  id_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
  conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$id_token")

  if list_resources webservice "$conjur_token" | grep -q "authn-jwt/github1"; then
    pass "JWT authenticator github1 present"
  else
    bad "JWT authenticator github1 not found"
  fi

  if list_resources host "$conjur_token" | grep -q "$workload"; then
    pass "workload host $workload present"
  else
    bad "workload host $workload not found"
  fi

  if list_resources group "$conjur_token" | grep -q "${SAFE_NAME}/delegation/consumers"; then
    pass "safe delegation group for $SAFE_NAME present"
  else
    bad "safe delegation group for $SAFE_NAME not found (synchronization incomplete?)"
  fi

  printf "\n== GitHub repository %s ==\n" "$GH_REPO"
  if ! command -v gh >/dev/null 2>&1; then
    bad "gh CLI not installed; cannot validate GitHub configuration"
  else
    local vars secrets envs v e
    vars=$(gh variable list --repo "$GH_REPO" --json name --jq '.[].name' 2>/dev/null)
    secrets=$(gh secret list --repo "$GH_REPO" --json name --jq '.[].name' 2>/dev/null)
    envs=$(gh api "repos/$GH_REPO/environments" --jq '.environments[].name' 2>/dev/null)

    for v in SM_URL SM_ACCOUNT SM_JWT_AUTHN_ID SM_SECRET_ID_1 SM_SECRET_ID_2; do
      if printf '%s\n' "$vars" | grep -qx "$v"; then pass "variable $v"; else bad "variable $v missing"; fi
    done
    for v in SM_USERNAME SM_API_KEY; do
      if printf '%s\n' "$secrets" | grep -qx "$v"; then pass "secret $v"; else bad "secret $v missing"; fi
    done
    for e in ${GH_ENVIRONMENTS:-dev staging main terraform}; do
      if printf '%s\n' "$envs" | grep -qx "$e"; then pass "environment $e"; else bad "environment $e missing"; fi
    done
  fi

  printf "\n"
  if [ "$FAIL" -ne 0 ]; then
    printf "Validation FAILED\n" >&2
    exit 1
  fi
  printf "Validation PASSED\n"
}

main "$@"
