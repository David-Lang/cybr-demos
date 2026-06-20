#!/usr/bin/env bash
# M1 acceptance: SWA platform (Server + Agent) and RSA trust domain registered.
set -uo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init >/dev/null 2>&1 || { echo "[FAIL] could not load setup/vars.env"; exit 1; }

rc=0
ok()   { printf '[OK]   %s\n' "$1"; }
bad()  { printf '[FAIL] %s\n' "$1"; rc=1; }

printf '\n========== SWA smoke M1 — platform ==========\n\n'

if kubectl get deploy/swa-server -n "$SWA_NAMESPACE" >/dev/null 2>&1 \
   && [[ "$(kubectl get deploy/swa-server -n "$SWA_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" == "1" ]]; then
  ok "SWA Server ready"
else
  bad "SWA Server not ready in $SWA_NAMESPACE"
fi

desired="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
readyd="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
if [[ "${desired:-0}" -gt 0 && "${readyd:-0}" == "${desired:-0}" ]]; then
  ok "SWA Agent ready ($readyd/$desired nodes)"
else
  bad "SWA Agent not ready ($readyd/${desired:-0})"
fi

tf_vars="$demo_path/setup/swa/terraform/terraform.tfvars"
if [[ -f "$tf_vars" ]]; then
  if grep -q 'jwt_signature_algorithm.*RS256' "$tf_vars" 2>/dev/null \
     && grep -q 'jwt_signing_key_type.*RSA_2048' "$tf_vars" 2>/dev/null; then
    ok "Trust domain configured for RSA / RS256 (authn-jwt compatible)"
  else
    bad "terraform.tfvars missing RS256/RSA_2048 — JWT authenticator may reject EC-signed SVIDs"
  fi
else
  bad "terraform.tfvars not found — run setup/swa/register.sh"
fi

if [[ -f "$demo_path/setup/swa/terraform/swa_outputs.env" ]]; then
  ok "SWA terraform outputs present (server registered on tenant)"
else
  bad "Missing setup/swa/terraform/swa_outputs.env — run setup/swa/register.sh"
fi

printf '\n'
[[ $rc -eq 0 ]] && printf '========== M1 PASS ==========\n\n' \
               || printf '========== M1 FAIL ==========\n\n'
exit $rc
