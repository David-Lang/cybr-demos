#!/usr/bin/env bash
# Prerequisite triage for the SWA demo before go.sh.
set -euo pipefail

fail() { printf '\n[FAIL] %s\n' "$1" >&2; exit 1; }
pass() { printf '[OK] %s\n' "$1"; }

demo_path="$(cd "$(dirname "$0")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$demo_path/../../../.." && pwd)}"

vars_env="$demo_path/setup/vars.env"
tenant_vars="$CYBR_DEMOS_PATH/demos/tenant_vars.sh"

[[ -f "$tenant_vars" ]] || fail "Missing $tenant_vars"
[[ -f "$vars_env" ]] || fail "Missing $vars_env — copy from setup/vars.env.example."

printf '\n========== SWA demo — prerequisite check ==========\n\n'

printf -- '--- 1) Local tools ---\n'
for c in curl jq bash mktemp kubectl helm terraform unzip; do
  command -v "$c" >/dev/null 2>&1 || fail "Missing required command: $c"
done
pass "curl, jq, kubectl, helm, terraform, unzip present"
if ! command -v minikube >/dev/null 2>&1; then
  printf '[WARN] minikube not on PATH — image loading will be skipped (load images manually).\n'
else
  pass "minikube present"
fi
if ! command -v gum >/dev/null 2>&1; then
  printf '[WARN] gum not on PATH — demo.sh falls back to plain output. For the polished\n'
  printf '       presentation install it: brew install gum  (https://github.com/charmbracelet/gum)\n'
else
  pass "gum present (polished demo.sh presentation enabled)"
fi

printf -- '\n--- 2) Tenant credentials ---\n'
set -a
# shellcheck source=/dev/null
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# shellcheck source=/dev/null
source "$vars_env"
set +a
for v in TENANT_ID TENANT_SUBDOMAIN CLIENT_ID CLIENT_SECRET; do
  [[ -n "${!v:-}" ]] || fail "$v is empty after sourcing tenant_vars."
done
pass "TENANT_ID=$TENANT_ID TENANT_SUBDOMAIN=$TENANT_SUBDOMAIN (secret not printed)"

printf -- '\n--- 3) SWA release artifact ---\n'
zip_path="${SWA_RELEASE_ZIP:-}"
[[ -z "$zip_path" ]] && zip_path="$(find "${SWA_RELEASE_DIR:-$HOME/Downloads}" -maxdepth 1 -name 'Secure Workload Access*.zip' 2>/dev/null | sort | tail -1)"
[[ -n "$zip_path" && -f "$zip_path" ]] || fail "SWA release zip not found. Set SWA_RELEASE_ZIP or drop it in SWA_RELEASE_DIR."
pass "release zip: $zip_path"

printf -- '\n--- 4) Kubernetes cluster ---\n'
kubectl get nodes >/dev/null 2>&1 || fail "kubectl get nodes failed — start minikube and set the context."
ctx="$(kubectl config current-context 2>/dev/null || echo '?')"
pass "Kubernetes API reachable (context: $ctx)"
kubectl get --raw /openid/v1/jwks >/dev/null 2>&1 || fail "/openid/v1/jwks not reachable — needed for the SWA server registration."
pass "cluster OIDC JWKS reachable"

printf -- '\n--- 5) Platform + Conjur token ---\n'
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET" 2>/dev/null || true)"
[[ -n "$identity_token" ]] || fail "get_identity_token failed — check TENANT_ID, CLIENT_ID/SECRET."
pass "Platform token acquired (${#identity_token} chars)"
conjur_token="$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token" 2>/dev/null || true)"
[[ -n "$conjur_token" ]] || fail "get_conjur_token failed — check TENANT_SUBDOMAIN."
pass "Conjur token acquired (${#conjur_token} chars)"

printf '\n========== All checks passed. Run: bash go.sh ==========\n\n'
