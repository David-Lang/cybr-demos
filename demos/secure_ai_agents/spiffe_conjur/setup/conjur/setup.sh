#!/bin/bash
# setup/conjur/setup.sh
#
# Stage 4: configure CyberArk Conjur Cloud authn-jwt to trust SPIRE's JWT-SVIDs
# and seed the demo secret. Uses direct REST via the shared utility functions
# in demos/utility/ubuntu/{identity,conjur}_functions.sh -- no Conjur CLI.
#
# Steps:
#   1. Get an ISPSS identity token (CLIENT_ID/CLIENT_SECRET from tenant_vars.sh).
#   2. Exchange for a Conjur Cloud session token.
#   3. Render the four policy templates with envsubst.
#   4. Apply each policy at the correct branch.
#   5. Set the four authenticator variables (jwks-uri, issuer, ...).
#   6. Enable the authenticator.
#   7. Set the demo secret value.
#   8. Patch the in-cluster ConfigMap conjur-config so the attested-agent uses
#      the right CONJUR_URL.

# shellcheck disable=SC1091
set -euo pipefail

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  CYBR_DEMOS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
  export CYBR_DEMOS_PATH
fi

demo_path="$CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

stage_dir="$demo_path/setup/conjur"
oidc_env="$demo_path/setup/.oidc.env"

[ -f "$oidc_env" ] || { printf "[FAIL] missing %s — run setup/oidc/setup.sh first\n" "$oidc_env" >&2; exit 1; }
# shellcheck disable=SC1090
source "$oidc_env"

for var in TENANT_ID TENANT_SUBDOMAIN CLIENT_ID CLIENT_SECRET OIDC_PUBLIC_URL DEMO_SECRET_VALUE; do
  if [ -z "${!var:-}" ]; then
    printf "[FAIL] required env var %s is empty (check tenant_vars.sh and oidc stage)\n" "$var" >&2
    exit 1
  fi
done

kctx() { kubectl --context "$MINIKUBE_PROFILE" "$@"; }

render_policy() {
  # $1 = source policy file. `set -a` exported vars.env values; envsubst inherits them.
  # Single-quoted arg is envsubst's variable allowlist syntax (intentional, not a shell expansion).
  # shellcheck disable=SC2016
  envsubst '${CONJUR_AUTHN_SERVICE_ID} ${SPIFFE_HOST_ID} ${CONJUR_HOSTS_BRANCH}' < "$1"
}

# ─── 1 + 2: Tokens ───────────────────────────────────────────────────────────
printf "\n[INFO] Conjur: getting ISPSS identity token (tenant: %s)\n" "$TENANT_ID"
identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")

printf "[INFO] Conjur: exchanging for Conjur Cloud session token\n"
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")

# ─── 3 + 4: Render + apply policies ──────────────────────────────────────────
printf "\n[INFO] Conjur: applying policy 01-authn-jwt-spiffe.yaml -> conjur/authn-jwt\n"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-jwt" \
  "$(render_policy "$stage_dir/policy/01-authn-jwt-spiffe.yaml")" >/dev/null

printf "[INFO] Conjur: applying policy 02-spiffe-apps-hosts.yaml -> data\n"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(render_policy "$stage_dir/policy/02-spiffe-apps-hosts.yaml")" >/dev/null

printf "[INFO] Conjur: applying policy 03-authn-jwt-grant.yaml -> %s\n" "$CONJUR_AUTHN_BRANCH"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "$CONJUR_AUTHN_BRANCH" \
  "$(render_policy "$stage_dir/policy/03-authn-jwt-grant.yaml")" >/dev/null

printf "[INFO] Conjur: applying policy 04-secret-access.yaml -> data\n"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(render_policy "$stage_dir/policy/04-secret-access.yaml")" >/dev/null

# ─── 5: Authenticator variables ──────────────────────────────────────────────
printf "\n[INFO] Conjur: setting authenticator variables (issuer = %s)\n" "$OIDC_PUBLIC_URL"
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" "$CONJUR_AUTHN_BRANCH/jwks-uri"           "$OIDC_PUBLIC_URL/keys" >/dev/null
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" "$CONJUR_AUTHN_BRANCH/issuer"             "$OIDC_PUBLIC_URL"      >/dev/null
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" "$CONJUR_AUTHN_BRANCH/token-app-property" "sub"                   >/dev/null
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" "$CONJUR_AUTHN_BRANCH/identity-path"      "$CONJUR_HOSTS_BRANCH"  >/dev/null

# ─── 6: Enable authenticator ─────────────────────────────────────────────────
printf "[INFO] Conjur: enabling authenticator authn-jwt/%s\n" "$CONJUR_AUTHN_SERVICE_ID"
activate_conjur_service "$TENANT_SUBDOMAIN" "$conjur_token" "authn-jwt/$CONJUR_AUTHN_SERVICE_ID" >/dev/null

# ─── 7: Seed demo secret ─────────────────────────────────────────────────────
printf "[INFO] Conjur: setting %s = <DEMO_SECRET_VALUE>\n" "$CONJUR_SECRET_VARIABLE"
encoded_secret_id=$(printf '%s' "$CONJUR_SECRET_VARIABLE" | sed 's|/|%2F|g')
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" "$encoded_secret_id" "$DEMO_SECRET_VALUE" >/dev/null

# ─── 8: Patch in-cluster ConfigMap ───────────────────────────────────────────
printf "\n[INFO] Conjur: patching in-cluster ConfigMap %s/conjur-config\n" "$WORKLOADS_NAMESPACE"
kctx -n "$WORKLOADS_NAMESPACE" create configmap conjur-config \
  --from-literal=CONJUR_URL="https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud/api" \
  --from-literal=CONJUR_ACCOUNT="conjur" \
  --from-literal=CONJUR_AUTHENTICATOR_ID="authn-jwt/$CONJUR_AUTHN_SERVICE_ID" \
  --from-literal=CONJUR_VARIABLE="$CONJUR_SECRET_VARIABLE" \
  --dry-run=client -o yaml | kctx apply -f - >/dev/null

if kctx -n "$WORKLOADS_NAMESPACE" get pod "$ATTESTED_AGENT_NAME" >/dev/null 2>&1; then
  printf "[INFO] Conjur: restarting %s/%s to pick up the new ConfigMap\n" "$WORKLOADS_NAMESPACE" "$ATTESTED_AGENT_NAME"
  kctx -n "$WORKLOADS_NAMESPACE" delete pod "$ATTESTED_AGENT_NAME" --ignore-not-found >/dev/null
  kctx -n "$WORKLOADS_NAMESPACE" wait --for=condition=Ready "pod/$ATTESTED_AGENT_NAME" --timeout=120s >/dev/null 2>&1 || true
fi

printf "\n[INFO] Conjur: stage complete\n"
printf "[INFO] Conjur:   Authenticator : authn-jwt/%s\n" "$CONJUR_AUTHN_SERVICE_ID"
printf "[INFO] Conjur:   JWKS URL      : %s/keys\n"      "$OIDC_PUBLIC_URL"
printf "[INFO] Conjur:   Issuer        : %s\n"           "$OIDC_PUBLIC_URL"
printf "[INFO] Conjur:   Workload host : %s\n"           "$SPIFFE_HOST_ID"
printf "[INFO] Conjur:   Demo secret   : %s\n"           "$CONJUR_SECRET_VARIABLE"
