#!/usr/bin/env bash
# Prerequisite check for demos/secrets_manager/jenkins
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/jenkins_demo_lib.sh"

fail() {
  printf '\n[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() { printf '[OK] %s\n' "$1"; }

jenkins_demo_init

[[ -n "${CYBR_DEMOS_PATH:-}" ]] || fail "Set CYBR_DEMOS_PATH to the cybr-demos repo root."
[[ -d "$JENKINS_DEMO_DIR" ]] || fail "Missing demo dir: $JENKINS_DEMO_DIR"
[[ -f "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" ]] || fail "Missing demos/tenant_vars.sh"

if [[ ! -f "$JENKINS_VARS_FILE" ]]; then
  if [[ -f "$JENKINS_DEMO_DIR/setup/vars.env.example" ]]; then
    fail "Missing $JENKINS_VARS_FILE — run: cp setup/vars.env.example setup/vars.env"
  fi
  fail "Missing $JENKINS_VARS_FILE"
fi

printf '\n========== Secrets Manager / Jenkins — prerequisite check ==========\n\n'

printf '%s\n' '--- 1) Local tools ---'
for c in curl jq bash docker; do
  command -v "$c" >/dev/null 2>&1 || fail "Missing required command: $c"
done
pass "curl, jq, bash, docker present"

jenkins_load_env

[[ -n "${SAFE_NAME:-}" ]] || fail "SAFE_NAME empty in setup/vars.env"
[[ -n "${DEPLOY_PROFILE:-}" ]] || fail "DEPLOY_PROFILE empty (aws or local)"
pass "Demo vars loaded from setup/vars.env"

printf '\n--- 2) CyberArk tenant credentials ---\n'
if [[ ! -f "$JENKINS_LOCAL_VARS" ]]; then
  fail "Missing $JENKINS_LOCAL_VARS — run: cp demos/tenant_vars.local.sh.example demos/tenant_vars.local.sh"
fi
pass "Found demos/tenant_vars.local.sh"

if ! cyberark_creds_configured; then
  fail "Edit demos/tenant_vars.local.sh — set TENANT_ID, CLIENT_ID, CLIENT_SECRET (not placeholders)"
fi
pass "CyberArk credentials configured"

case "${DEPLOY_PROFILE}" in
  aws)
    if ! curl -sf --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-hostname >/dev/null 2>&1; then
      printf '[WARN] EC2 IMDS not reachable — aws profile expects a lab VM with public hostname\n' >&2
    else
      pass "EC2 metadata endpoint reachable (aws profile)"
    fi
    ;;
  local)
    if command -v cloudflared >/dev/null 2>&1; then
      pass "cloudflared present (local profile, optional public tunnel)"
    else
      printf '[INFO] cloudflared not installed — local profile will stay on http://127.0.0.1 (default public-keys mode does not need a tunnel)\n'
    fi
    ;;
  *)
    fail "DEPLOY_PROFILE must be aws or local (got: $DEPLOY_PROFILE)"
    ;;
esac

printf '\n--- 3) DNS: Secrets Manager host ---\n'
sm_host="${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud"
if curl -sf --connect-timeout 5 "https://${sm_host}/" >/dev/null 2>&1; then
  pass "HTTPS reachable: $sm_host"
else
  printf '[WARN] Could not reach https://%s (check network/VPN)\n' "$sm_host" >&2
fi

printf '\n--- 4) ISPSS OAuth client_credentials token ---\n'
id_host="${TENANT_ID}.id.cyberark.cloud"
if ! curl -sf --connect-timeout 5 -o /dev/null "https://${id_host}/"; then
  printf '[WARN] Identity host https://%s not reachable — token check skipped.\n' "$id_host" >&2
  printf '       Confirm TENANT_ID matches your Identity tenant label (portal redirects to <label>.id.cyberark.cloud/login).\n' >&2
else
  token_resp=$(curl -sS -X POST "https://${id_host}/oauth2/platformtoken" \
    -H 'X-IDAP-NATIVE-CLIENT: true' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H 'Accept: application/json' \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" 2>&1) || token_resp=""
  if printf '%s' "$token_resp" | jq -e '.access_token // empty' >/dev/null 2>&1; then
    pass "ISPSS access_token issued for ${CLIENT_ID}"
  else
    err_desc=$(printf '%s' "$token_resp" | jq -r '.error_description // .error // "unknown"' 2>/dev/null)
    printf '[FAIL] ISPSS rejected client_credentials for %s\n' "$CLIENT_ID" >&2
    printf '       reason: %s\n' "$err_desc" >&2
    printf '       fix:    rotate CLIENT_SECRET in Identity Admin (Core Services > Users) AND\n' >&2
    printf '               ensure user has "Is OAuth confidential client" + a role granting Privilege Cloud / SM API access.\n' >&2
    exit 1
  fi
fi

printf '\n[OK] Prerequisites look good. Run: bash go.sh\n\n'
