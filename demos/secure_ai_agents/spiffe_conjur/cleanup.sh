#!/bin/bash
# secure_ai_agents/spiffe_conjur — full teardown.
#
# What it does (in order):
#   1. Stop the cloudflared tunnel + port-forward.
#   2. Replace the Conjur Cloud policies in this branch with empty bodies so
#      the authenticator + workload host + demo secret are removed cleanly.
#   3. Delete the minikube profile (also removes all in-cluster state).
#
# Pass --keep-conjur to skip step 2 (e.g., when the URL changed and you only
# want to recycle the local cluster). Pass --keep-cluster to skip step 3.

# shellcheck disable=SC1091
set -euo pipefail

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  CYBR_DEMOS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  export CYBR_DEMOS_PATH
fi

demo_path="$CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

KEEP_CONJUR=0
KEEP_CLUSTER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-conjur) KEEP_CONJUR=1 ;;
    --keep-cluster) KEEP_CLUSTER=1 ;;
    *) printf "[WARN] unknown flag: %s\n" "$1" ;;
  esac
  shift
done

# ─── 1. Stop tunnel ──────────────────────────────────────────────────────────
printf "\n[INFO] Cleanup: stopping cloudflared tunnel\n"
"$demo_path/setup/oidc/setup.sh" --stop || true
rm -f "$demo_path/setup/.oidc.env"

# ─── 2. Wipe Conjur policies + secret ────────────────────────────────────────
if [ "$KEEP_CONJUR" -eq 0 ]; then
  printf "\n[INFO] Cleanup: removing Conjur Cloud policies + demo secret\n"
  if [ -z "${TENANT_ID:-}" ] || [ -z "${TENANT_SUBDOMAIN:-}" ] || [ -z "${CLIENT_ID:-}" ] || [ -z "${CLIENT_SECRET:-}" ]; then
    printf "[WARN] Cleanup: tenant_vars not set — skipping Conjur cleanup\n"
  else
    identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET" 2>/dev/null || true)
    if [ -n "$identity_token" ]; then
      conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token" 2>/dev/null || true)
      if [ -n "$conjur_token" ]; then
        # Replace each branch with an empty policy to remove all entries we created.
        for branch in "$CONJUR_AUTHN_BRANCH" "$CONJUR_HOSTS_BRANCH" "$CONJUR_SECRET_BRANCH"; do
          printf "[INFO] Cleanup: PUT empty policy at branch %s\n" "$branch"
          curl --silent --request PUT \
            --location "https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud/api/policies/conjur/policy/$branch" \
            --header "Authorization: Token token=\"$conjur_token\"" \
            --header 'Content-Type: text/plain' \
            --data '' >/dev/null || true
        done
      else
        printf "[WARN] Cleanup: could not get Conjur token — skipping Conjur cleanup\n"
      fi
    else
      printf "[WARN] Cleanup: could not get identity token — skipping Conjur cleanup\n"
    fi
  fi
fi

# ─── 3. Tear down minikube ───────────────────────────────────────────────────
if [ "$KEEP_CLUSTER" -eq 0 ]; then
  if minikube -p "$MINIKUBE_PROFILE" status >/dev/null 2>&1; then
    printf "\n[INFO] Cleanup: deleting minikube profile %s\n" "$MINIKUBE_PROFILE"
    minikube delete -p "$MINIKUBE_PROFILE"
  else
    printf "[INFO] Cleanup: minikube profile %s not running\n" "$MINIKUBE_PROFILE"
  fi
fi

# Remove rendered templates + tunnel state
rm -f "$demo_path/setup/workloads/manifests/40-attested-agent.rendered.yaml"
rm -rf "$demo_path/setup/oidc/state"

printf "\n[INFO] Cleanup complete.\n"
