# Shared helpers for demos/secrets_manager/jenkins (source, do not execute).
# shellcheck shell=bash

jenkins_demo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

jenkins_demo_init() {
  export JENKINS_DEMO_DIR
  JENKINS_DEMO_DIR="$(jenkins_demo_root)"
  export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$JENKINS_DEMO_DIR/../../.." && pwd)}"
  export JENKINS_VARS_FILE="$JENKINS_DEMO_DIR/setup/vars.env"
  export JENKINS_ENV_FILE="$JENKINS_DEMO_DIR/setup/.jenkins.env"
  export JENKINS_PIPELINE_FILE="$JENKINS_DEMO_DIR/setup/jenkins/pipeline/get_secrets.groovy"
  export JENKINS_PIPELINE_TMPL="$JENKINS_DEMO_DIR/setup/jenkins/pipeline/get_secrets.groovy.tmpl"
  export JENKINS_LOCAL_VARS="$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh"
  export JENKINS_EDGE_DIR="$JENKINS_DEMO_DIR/setup/edge"
  export JENKINS_EDGE_INSTALL="$JENKINS_EDGE_DIR/install.sh"
}

jenkins_load_env() {
  jenkins_demo_init
  if [[ -z "${_JENKINS_DEMO_ENV_LOADED:-}" ]]; then
    # shellcheck disable=SC1091
    source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
    _JENKINS_DEMO_ENV_LOADED=1
  fi
  if [[ -f "$JENKINS_VARS_FILE" ]]; then
    # shellcheck disable=SC1091
    source "$JENKINS_VARS_FILE"
  fi
  if [[ -f "$JENKINS_ENV_FILE" ]]; then
    # shellcheck disable=SC1091
    source "$JENKINS_ENV_FILE"
  fi
}

cyberark_creds_configured() {
  jenkins_load_env 2>/dev/null || true
  local v
  for v in TENANT_ID CLIENT_ID CLIENT_SECRET TENANT_SUBDOMAIN; do
    if [[ -z "${!v:-}" ]]; then
      return 1
    fi
    if [[ "${!v}" == SET_* ]] || [[ "${!v}" == your-* ]]; then
      return 1
    fi
  done
  return 0
}

render_jenkins_pipeline() {
  jenkins_load_env
  if [[ ! -f "$JENKINS_PIPELINE_TMPL" ]]; then
    printf 'Missing pipeline template: %s\n' "$JENKINS_PIPELINE_TMPL" >&2
    return 1
  fi
  if [[ -z "${SAFE_NAME:-}" ]]; then
    printf 'SAFE_NAME not set in setup/vars.env\n' >&2
    return 1
  fi
  sed "s/{{SAFE_NAME}}/${SAFE_NAME}/g" "$JENKINS_PIPELINE_TMPL" >"$JENKINS_PIPELINE_FILE"
  printf 'Rendered %s\n' "$JENKINS_PIPELINE_FILE"
}

pipeline_is_rendered() {
  jenkins_demo_init
  [[ -s "$JENKINS_PIPELINE_FILE" ]] && grep -q 'conjurSecretCredential' "$JENKINS_PIPELINE_FILE" 2>/dev/null
}

jenkins_container_running() {
  local container="${JENKINS_CONTAINER:-cybr-jenkins}"
  docker ps --filter "name=${container}" --filter status=running -q 2>/dev/null | grep -q .
}

jenkins_job_exists() {
  local container="${JENKINS_CONTAINER:-cybr-jenkins}"
  local job="${1:-global-credentials-demo}"
  docker exec "$container" test -f "/var/jenkins_home/jobs/${job}/config.xml" 2>/dev/null
}

jenkins_plugin_configured() {
  local container="${JENKINS_CONTAINER:-cybr-jenkins}"
  docker exec "$container" grep -q 'selectAuthenticator>JWT' \
    /var/jenkins_home/org.conjur.jenkins.configuration.GlobalConjurConfiguration.xml 2>/dev/null
}

jenkins_automation_ready() {
  pipeline_is_rendered && jenkins_container_running && jenkins_job_exists && jenkins_plugin_configured
}

#//------------------------------------------------------------------------------------------------
# Edge helpers (only used when CONJUR_AUTH_TARGET=edge)
#//------------------------------------------------------------------------------------------------

edge_default_data_dir() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    printf '%s' "$HOME/cyberark"
  else
    printf '%s' "/cyberark"
  fi
}

edge_resolved_data_dir() {
  if [[ -n "${EDGE_DATA_DIR:-}" ]]; then
    printf '%s' "$EDGE_DATA_DIR"
  else
    edge_default_data_dir
  fi
}

edge_container_running() {
  local container="${EDGE_CONTAINER:-cybr-conjur-edge}"
  docker ps --filter "name=${container}" --filter status=running -q 2>/dev/null | grep -q .
}

edge_health_ok() {
  local host="${EDGE_HOST:-host.docker.internal}"
  local port="${EDGE_HEALTH_PORT:-444}"
  curl -sf --max-time 3 "http://127.0.0.1:${port}/health" -o /dev/null 2>/dev/null \
    || curl -sfk --max-time 3 "https://${host}:${port}/health" -o /dev/null 2>/dev/null
}

edge_appliance_url() {
  local host="${EDGE_HOST:-host.docker.internal}"
  local port="${EDGE_PORT:-443}"
  printf 'https://%s:%s/api' "$host" "$port"
}

conjur_appliance_url() {
  case "${CONJUR_AUTH_TARGET:-cloud}" in
    edge) edge_appliance_url ;;
    *)    printf 'https://%s.secretsmgr.cyberark.cloud/api' "${TENANT_SUBDOMAIN}" ;;
  esac
}

resolved_jwks_url_for_jwks_uri_mode() {
  if [[ -n "${JWKS_URL_OVERRIDE:-}" ]]; then
    printf '%s' "$JWKS_URL_OVERRIDE"
    return
  fi
  if [[ "${CONJUR_AUTH_TARGET:-cloud}" == "edge" ]]; then
    printf 'http://%s:%s/jwtauth/conjur-jwk-set' \
      "${EDGE_JWKS_HOST_FROM_EDGE:-host.docker.internal}" "${JENKINS_PORT:-8081}"
    return
  fi
  printf '%s' "${JENKINS_JWKS_URI:-}"
}
