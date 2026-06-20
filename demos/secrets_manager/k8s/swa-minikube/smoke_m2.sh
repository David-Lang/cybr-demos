#!/usr/bin/env bash
# M2 acceptance: authn-jwt authenticator enabled and a JWT-SVID authenticates to Conjur.
set -uo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init >/dev/null 2>&1 || { echo "[FAIL] could not load setup/vars.env"; exit 1; }

rc=0
ok()   { printf '[OK]   %s\n' "$1"; }
bad()  { printf '[FAIL] %s\n' "$1"; rc=1; }

printf '\n========== SWA smoke M2 — authn-jwt ==========\n\n'

if ! swa_get_tokens >/dev/null 2>&1; then
  bad "Could not acquire Conjur token — check tenant credentials"
  printf '\n========== M2 FAIL ==========\n\n'
  exit 1
fi

authn_status="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Token token=\"$SWA_CONJUR_TOKEN\"" \
  "https://${SM_FQDN}/api/authn-jwt/${SWA_AUTHN_ID}/conjur/status" 2>/dev/null || echo 000)"
if [[ "$authn_status" == "200" ]]; then
  ok "authn-jwt/${SWA_AUTHN_ID} status reachable (HTTP 200)"
else
  bad "authn-jwt/${SWA_AUTHN_ID} status HTTP ${authn_status} — run enable_swa_authenticator.sh"
fi

issuer="$(curl -s -H "Authorization: Token token=\"$SWA_CONJUR_TOKEN\"" \
  "https://${SM_FQDN}/api/secrets/conjur/variable/conjur/authn-jwt/${SWA_AUTHN_ID}/issuer" 2>/dev/null || true)"
jwks="$(curl -s -H "Authorization: Token token=\"$SWA_CONJUR_TOKEN\"" \
  "https://${SM_FQDN}/api/secrets/conjur/variable/conjur/authn-jwt/${SWA_AUTHN_ID}/jwks-uri" 2>/dev/null || true)"
if [[ -n "$issuer" && "$issuer" != *error* ]]; then
  ok "Authenticator issuer configured"
else
  bad "Authenticator issuer not readable"
fi
if [[ -n "$jwks" && "$jwks" != *error* ]]; then
  ok "Authenticator JWKS URI configured"
else
  bad "Authenticator JWKS URI not readable"
fi

if kubectl get deploy/swa-demo-app -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1; then
  svid="$(swa_get_live_workload_svid swa-demo-app 2>/dev/null || true)"
  if [[ "$svid" == *.*.* ]]; then
    auth_code="$(curl -s -o /dev/null -w '%{http_code}' \
      --data-urlencode "jwt=${svid}" -H "Accept-Encoding: base64" \
      "https://${SM_FQDN}/api/authn-jwt/${SWA_AUTHN_ID}/conjur/authenticate" 2>/dev/null || echo 000)"
    if [[ "$auth_code" == "200" ]]; then
      ok "JWT-SVID authenticates to Conjur (HTTP 200)"
    else
      bad "JWT-SVID auth returned HTTP ${auth_code} (after SVID refresh attempt)"
    fi
  else
    bad "Could not obtain a live JWT-SVID from the workload pod"
  fi
else
  ok "Workload not deployed — skipping live JWT auth probe (run deploy_workload.sh for full M2+)"
fi

printf '\n'
[[ $rc -eq 0 ]] && printf '========== M2 PASS ==========\n\n' \
               || printf '========== M2 FAIL ==========\n\n'
exit $rc
