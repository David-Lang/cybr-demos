#!/bin/bash
# Exit 0 when Jenkins + CyberArk backend are ready for demo.sh / pipeline build.
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/jenkins_demo_lib.sh"
jenkins_demo_init

port="${JENKINS_PORT:-8081}"
fail=0

ok() { printf '[OK] %s\n' "$1"; }
bad() { printf '[FAIL] %s\n' "$1"; fail=1; }

if jenkins_container_running; then
  ok 'Jenkins container running'
else
  bad 'Jenkins container running'
fi

if curl -sf "http://127.0.0.1:${port}/login" -o /dev/null; then
  ok "Jenkins UI http://127.0.0.1:${port}"
else
  bad "Jenkins UI http://127.0.0.1:${port}"
fi

if pipeline_is_rendered; then
  ok 'Pipeline script rendered'
else
  bad 'Pipeline script rendered'
fi

if [[ -f "$JENKINS_ENV_FILE" ]]; then
  ok 'setup/.jenkins.env present'
else
  bad 'setup/.jenkins.env present'
fi

if jenkins_job_exists; then
  ok 'Pipeline job global-credentials-demo'
else
  bad 'Pipeline job global-credentials-demo'
fi

if jenkins_plugin_configured; then
  ok 'Conjur plugin JWT configured'
else
  bad 'Conjur plugin JWT configured'
fi

if [[ -f "$JENKINS_LOCAL_VARS" ]] && cyberark_creds_configured; then
  jenkins_load_env
  if get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET" >/dev/null 2>&1; then
    ok 'CyberArk identity token'
  else
    bad 'CyberArk identity token (VPN / creds?)'
  fi
else
  bad "Missing or incomplete $JENKINS_LOCAL_VARS"
fi

if curl -sf --connect-timeout 5 "http://127.0.0.1:${port}/jwtauth/conjur-jwk-set" -o /dev/null 2>/dev/null; then
  case "${JWT_TRUST_MODE:-public-keys}" in
    public-keys) ok 'Local JWKS endpoint up (mirrored into Conjur public-keys by finish_setup.sh)' ;;
    jwks-uri)    ok 'Local JWKS endpoint up (Conjur/Edge fetches it via jwks-uri)' ;;
  esac
else
  bad 'Local JWKS endpoint not responding — run: bash finish_setup.sh'
fi

if [[ "${CONJUR_AUTH_TARGET:-cloud}" == "edge" ]]; then
  if edge_container_running; then
    ok "Edge container running (${EDGE_CONTAINER:-cybr-conjur-edge})"
  else
    bad "Edge container not running — run: bash setup/edge/setup.sh"
  fi

  if edge_health_ok; then
    ok "Edge /health responding (port ${EDGE_HEALTH_PORT:-444})"
  else
    bad "Edge /health not responding — replication may not be complete yet"
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  printf '\nReady: bash demo.sh\n'
  printf 'Jenkins job: http://127.0.0.1:%s/job/global-credentials-demo/\n' "$port"
  exit 0
fi

printf '\nNot ready — run: bash go.sh (see demo_setup.md)\n'
exit 1
