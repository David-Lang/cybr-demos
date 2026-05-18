#!/usr/bin/env bash
# One-shot triage for demos/secrets_manager/k8s before ./setup.sh
# Usage (from anywhere):
#   export CYBR_DEMOS_PATH=/path/to/cybr-demos
#   bash "$CYBR_DEMOS_PATH/demos/secrets_manager/k8s/check_prereqs.sh"
set -euo pipefail

fail() {
  printf '\n[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() { printf '[OK] %s\n' "$1"; }

[[ -n "${CYBR_DEMOS_PATH:-}" ]] || fail "Set CYBR_DEMOS_PATH to the cybr-demos repo root."

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/k8s"
vars_env="$demo_path/setup/vars.env"
tenant_vars="$CYBR_DEMOS_PATH/demos/tenant_vars.sh"

[[ -d "$demo_path" ]] || fail "Missing demo dir: $demo_path (wrong CYBR_DEMOS_PATH?)"
[[ -f "$tenant_vars" ]] || fail "Missing $tenant_vars"
[[ -f "$vars_env" ]] || fail "Missing $vars_env — create it from the template in this folder (see demo_setup.md)."

printf '\n========== Secrets Manager / K8s — prerequisite check ==========\n\n'

printf '%s\n' '--- 1) Local tools ---'
for c in curl jq bash mktemp; do
  command -v "$c" >/dev/null 2>&1 || fail "Missing required command: $c"
done
pass "curl, jq, bash, mktemp present"
command -v kubectl >/dev/null 2>&1 || fail "kubectl not found — install kubectl and configure cluster access."
pass "kubectl present"
if command -v helm >/dev/null 2>&1; then
  pass "helm present (required for setup/k8s/setup.sh — installs External Secrets Operator and the demo chart)"
elif [[ "${SKIP_HELM_CHECK:-}" == "1" ]]; then
  printf '%s\n' "[WARN] helm not in PATH — skipped because SKIP_HELM_CHECK=1. Install before ./setup.sh: macOS: brew install helm" >&2
else
  fail "helm not found — ./setup.sh needs Helm 3 for this demo (ESO + Helm chart). Install: macOS: brew install helm. Or validate CyberArk only: SKIP_HELM_CHECK=1 bash \"$demo_path/check_prereqs.sh\""
fi

printf '\n--- 2) Tenant credentials (demos/tenant_vars.sh) ---\n'
set -a
# shellcheck disable=SC1090
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# shellcheck disable=SC1090
source "$vars_env"
set +a

[[ -n "${TENANT_ID:-}" ]] || fail "TENANT_ID is empty after sourcing tenant_vars."
[[ -n "${TENANT_SUBDOMAIN:-}" ]] || fail "TENANT_SUBDOMAIN is empty."
[[ -n "${CLIENT_ID:-}" ]] || fail "CLIENT_ID is empty."
[[ -n "${CLIENT_SECRET:-}" ]] || fail "CLIENT_SECRET is empty."

if [[ "${CLIENT_ID:-}" == SET_* ]] || [[ "${CLIENT_SECRET:-}" == SET_* ]]; then
  fail "CLIENT_ID / CLIENT_SECRET still look like placeholders in demos/tenant_vars.sh — set real OAuth confidential client credentials."
fi
pass "TENANT_ID=$TENANT_ID TENANT_SUBDOMAIN=$TENANT_SUBDOMAIN CLIENT_ID=$CLIENT_ID (secret not printed)"

printf '\n--- 3) DNS: Identity (ISPSS) host ---\n'
id_host="${TENANT_ID}.id.cyberark.cloud"
if command -v host >/dev/null 2>&1; then
  host "$id_host" || fail "DNS lookup failed for $id_host — fix network/VPN or TENANT_ID (must match https://<TENANT_ID>.id.cyberark.cloud)."
elif command -v dscacheutil >/dev/null 2>&1; then
  dscacheutil -q host -a name "$id_host" | head -n 5 || true
else
  printf '(skip DNS: install host(1) for DNS check)\n'
fi
pass "Resolved or skipped DNS for $id_host"

printf '\n--- 4) ISPSS platform token (same as vault/setup.sh) ---\n'
# Subshell: get_identity_token uses exit 1 on failure; we must not kill this script.
# Pass credentials via env so special characters in CLIENT_SECRET cannot break quoting.
export _K8S_PREQ_TENANT_ID="$TENANT_ID"
export _K8S_PREQ_CLIENT_ID="$CLIENT_ID"
export _K8S_PREQ_CLIENT_SECRET="$CLIENT_SECRET"
outf=$(mktemp)
set +e
bash -euo pipefail -c '
  export CYBR_DEMOS_PATH="'"$CYBR_DEMOS_PATH"'"
  set -a
  # shellcheck disable=SC1090
  source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
  set +a
  get_identity_token "$_K8S_PREQ_TENANT_ID" "$_K8S_PREQ_CLIENT_ID" "$_K8S_PREQ_CLIENT_SECRET"
' >"$outf" 2>&1
rc=$?
set -e
identity_token=$(cat "$outf")
rm -f "$outf"
unset _K8S_PREQ_TENANT_ID _K8S_PREQ_CLIENT_ID _K8S_PREQ_CLIENT_SECRET
if [[ "$rc" -ne 0 || -z "$identity_token" ]]; then
  printf '%s\n' "$identity_token" >&2
  fail "get_identity_token failed (exit $rc). Fix TENANT_ID (ISPSS id), CLIENT_ID/SECRET, OAuth confidential client, roles; optional CYBERARK_OAUTH_APP_ID for /oauth2/token/<appId>."
fi
pass "Platform token acquired (${#identity_token} chars)"

printf '\n--- 5) Secrets Manager / Conjur OIDC exchange ---\n'
export _K8S_PREQ_SUBDOMAIN="$TENANT_SUBDOMAIN"
export _K8S_PREQ_ID_TOKEN="$identity_token"
outf=$(mktemp)
set +e
bash -euo pipefail -c '
  export CYBR_DEMOS_PATH="'"$CYBR_DEMOS_PATH"'"
  set -a
  # shellcheck disable=SC1090
  source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
  set +a
  get_conjur_token "$_K8S_PREQ_SUBDOMAIN" "$_K8S_PREQ_ID_TOKEN"
' >"$outf" 2>&1
rc=$?
set -e
conjur_token=$(cat "$outf")
rm -f "$outf"
unset _K8S_PREQ_SUBDOMAIN _K8S_PREQ_ID_TOKEN
if [[ "$rc" -ne 0 || -z "$conjur_token" ]]; then
  printf '%s\n' "$conjur_token" >&2
  fail "get_conjur_token failed (exit $rc). Check TENANT_SUBDOMAIN for *.secretsmgr.cyberark.cloud and Conjur permissions."
fi
pass "Conjur token acquired (${#conjur_token} chars)"

printf '\n--- 6) Kubernetes cluster ---\n'
kubectl get nodes >/dev/null || fail "kubectl get nodes failed — start cluster (e.g. minikube start) and fix kubeconfig context."
pass "Kubernetes API reachable"

printf '\n========== All checks passed. Run: cd \"%s\" && ./setup.sh ==========\n\n' "$demo_path"
