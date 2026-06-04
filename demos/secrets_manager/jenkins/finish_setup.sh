#!/bin/bash
# finish_setup.sh — finalize Jenkins + Conjur JWT auth wiring.
#
# Idempotent. Safe to re-run. Assumes:
#   - Jenkins container "$JENKINS_CONTAINER" is running and reachable on $JENKINS_PORT
#   - The Conjur JWT authenticator exists at conjur/authn-jwt/$CONJUR_JWT_AUTHN_ID
#     (created either by setup/conjur/setup.sh or by the Secrets Manager SaaS UI)
#   - CyberArk creds in demos/tenant_vars.local.sh resolve via get_identity_token
#   - Jenkins admin login: env JENKINS_ADMIN_USER / JENKINS_ADMIN_PASSWORD
#     (defaults: admin / admin — set by us during interactive setup)
#
# Branches on JWT_TRUST_MODE (default: public-keys). Both modes are idempotent.
#
# Common steps (always run):
#   1. Optionally runs setup/vault/setup.sh + setup/conjur/setup.sh (init mode)
#   2. Renders + applies workload host + vault grant + JWT apps grant policies
#   3. Sets issuer / audience / token-app-property / identity-path variables
#   4. Creates Jenkins ConjurSecretCredentialsImpl entries (one per Conjur var
#      referenced in the rendered pipeline) — NO Jenkins restart
#   5. Pushes the rendered pipeline script to the global-credentials-demo job
#   6. Forces the Conjur Jenkins plugin to mint a JWT (materializes signing key)
#   7. Verifies the authenticator /status endpoint returns 200 OK
#      (skipped in edge + jwks-uri mode — see notes there)
#   8. Triggers a sanity build (skip via SKIP_BUILD=1)
#
# JWT_TRUST_MODE=public-keys (default):
#   - Adds 'public-keys' variable declaration to the authenticator policy if missing
#   - Fetches current Jenkins JWKS and writes it to conjur/authn-jwt/$id/public-keys
#   - PATCH-deletes 'jwks-uri' so Conjur uses the mirrored copy
#
# JWT_TRUST_MODE=jwks-uri:
#   - Adds 'jwks-uri' variable declaration if missing
#   - Sets jwks-uri to JWKS_URL_OVERRIDE (or JENKINS_JWKS_URI fallback).
#     For Edge mode, this is typically http://host.docker.internal:8081/...
#   - PATCH-deletes 'public-keys' so Conjur (or Edge) fetches keys at runtime

set -euo pipefail

demo_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$demo_dir/jenkins_demo_lib.sh"
jenkins_demo_init
jenkins_load_env

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$demo_dir/../../.." && pwd)}"

JENKINS_PORT="${JENKINS_PORT:-8081}"
JENKINS_CONTAINER="${JENKINS_CONTAINER:-cybr-jenkins}"
JENKINS_LOCAL_BASE_URL="${JENKINS_LOCAL_URL:-http://127.0.0.1:${JENKINS_PORT}}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-admin}"

CONJUR_JWT_AUTHN_ID="${CONJUR_JWT_AUTHN_ID:?CONJUR_JWT_AUTHN_ID required (setup/vars.env)}"
CONJUR_AUDIENCE="${CONJUR_AUDIENCE:-cyberark-conjur}"
SAFE_NAME="${SAFE_NAME:?SAFE_NAME required (setup/vars.env)}"
JWT_CLAIM_IDENTITY="${JWT_CLAIM_IDENTITY:?JWT_CLAIM_IDENTITY required (setup/vars.env)}"
TENANT_SUBDOMAIN="${TENANT_SUBDOMAIN:?TENANT_SUBDOMAIN required}"

# JWT_TRUST_MODE controls how Conjur validates Jenkins JWT signatures:
#   public-keys (default) — mirror live JWKS into Conjur 'public-keys' variable
#   jwks-uri              — set 'jwks-uri' variable; Conjur (or Edge) fetches JWKS over HTTP
JWT_TRUST_MODE="${JWT_TRUST_MODE:-public-keys}"
case "$JWT_TRUST_MODE" in
  public-keys|jwks-uri) ;;
  *) printf '[finish_setup ERR] JWT_TRUST_MODE must be "public-keys" or "jwks-uri" (got: %s)\n' "$JWT_TRUST_MODE" >&2; exit 1 ;;
esac

# Policy operations always go to Conjur Cloud SaaS (Edge replicates from there).
SM_BASE="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud"
AUTHN_BRANCH="conjur/authn-jwt/${CONJUR_JWT_AUTHN_ID}"

log()  { printf '\033[36m[finish_setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[finish_setup WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[finish_setup ERR]\033[0m %s\n' "$*" >&2; }

http_code() { printf '%s' "${1:-}"; }

require_jenkins_running() {
  if ! jenkins_container_running; then
    err "Jenkins container '$JENKINS_CONTAINER' is not running"
    err "Run: bash setup.sh   (or: bash go.sh)"
    exit 1
  fi
  if ! curl -sf --max-time 5 "$JENKINS_LOCAL_BASE_URL/login" >/dev/null; then
    err "Jenkins not reachable at $JENKINS_LOCAL_BASE_URL"
    exit 1
  fi
}

verify_jenkins_admin() {
  local code
  code=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' \
    -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    "$JENKINS_LOCAL_BASE_URL/api/json")
  if [[ "$code" != "200" ]]; then
    err "Jenkins admin login failed for user='${JENKINS_ADMIN_USER}' (HTTP ${code})"
    err "Set JENKINS_ADMIN_USER + JENKINS_ADMIN_PASSWORD env vars and re-run."
    exit 1
  fi
}

get_tokens() {
  identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
  if [[ -z "$identity_token" ]]; then err "identity_token empty"; exit 1; fi
  conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")
  if [[ -z "$conjur_token" ]]; then err "conjur_token empty"; exit 1; fi
}

conjur_get_var() {
  # echoes "HTTP <code>|<body>" — caller can split on |
  local var_id="$1"
  local body code
  body=$(curl -sS --max-time 10 -w '\n__HTTP__%{http_code}' \
    "$SM_BASE/api/secrets/conjur/variable/${var_id}" \
    -H "Authorization: Token token=\"${conjur_token}\"")
  code="${body##*__HTTP__}"
  body="${body%$'\n'__HTTP__*}"
  printf '%s|%s' "$code" "$body"
}

conjur_set_var() {
  local var_id="$1" value="$2"
  local code
  code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
    "$SM_BASE/api/secrets/conjur/variable/${var_id}" \
    -H "Authorization: Token token=\"${conjur_token}\"" \
    -H 'Content-Type: text/plain' \
    --data "$value")
  printf '%s' "$code"
}

conjur_apply_policy() { # POST (append)
  local branch="$1" body="$2"
  local resp code
  resp=$(curl -sS --max-time 15 -w '\n__HTTP__%{http_code}' \
    "$SM_BASE/api/policies/conjur/policy/${branch}" \
    -H "Authorization: Token token=\"${conjur_token}\"" \
    -H 'Content-Type: text/plain' \
    --data "$body")
  code="${resp##*__HTTP__}"
  printf '%s' "$code"
}

conjur_patch_policy() { # PATCH (supports !delete)
  local branch="$1" body="$2"
  local code
  code=$(curl -sS --max-time 15 -X PATCH -o /dev/null -w '%{http_code}' \
    "$SM_BASE/api/policies/conjur/policy/${branch}" \
    -H "Authorization: Token token=\"${conjur_token}\"" \
    -H 'Content-Type: text/plain' \
    --data "$body")
  printf '%s' "$code"
}

# ---------- 1) (Optional) run base setup first --------------------------------
run_base_setup_if_requested() {
  if [[ "${RUN_BASE_SETUP:-0}" == "1" ]]; then
    log "RUN_BASE_SETUP=1 -> running vault + conjur base setup first"
    (cd "$demo_dir/setup/vault" && ./setup.sh) || warn "vault setup non-zero"
    (cd "$demo_dir/setup/conjur" && ./setup.sh) || warn "conjur setup non-zero (this is OK if authenticator already exists)"
  fi
}

# ---------- 2) Render + apply policies ---------------------------------------
apply_policies() {
  log "Rendering policy templates from setup/conjur/*.tmpl.yaml"
  (
    cd "$demo_dir/setup/conjur"
    resolve_template workload1.tmpl.yaml workload1.yaml
    resolve_template jenkins_apps_vault_grant.tmpl.yaml jenkins_apps_vault_grant.yaml
    resolve_template jenkins_jwt_apps_grant.tmpl.yaml jenkins_jwt_apps_grant.yaml
  )

  local code
  log "Applying workload1 policy (data branch)"
  code=$(conjur_apply_policy "data" "$(cat "$demo_dir/setup/conjur/workload1.yaml")")
  [[ "$code" == "201" || "$code" == "200" ]] || warn "workload1 -> HTTP $code"

  log "Applying vault grant policy (data branch)"
  code=$(conjur_apply_policy "data" "$(cat "$demo_dir/setup/conjur/jenkins_apps_vault_grant.yaml")")
  [[ "$code" == "201" || "$code" == "200" ]] || warn "vault grant -> HTTP $code"

  log "Applying JWT apps grant policy ($AUTHN_BRANCH branch)"
  code=$(conjur_apply_policy "$AUTHN_BRANCH" "$(cat "$demo_dir/setup/conjur/jenkins_jwt_apps_grant.yaml")")
  [[ "$code" == "201" || "$code" == "200" ]] || warn "JWT apps grant -> HTTP $code"
}

# ---------- 3) Ensure public-keys variable declared in the authenticator -----
ensure_public_keys_variable() {
  log "Ensuring 'public-keys' variable exists in $AUTHN_BRANCH"
  # Append-only POST is idempotent: re-declaring an existing variable is a no-op.
  local code
  code=$(conjur_apply_policy "$AUTHN_BRANCH" "- !variable
  id: public-keys")
  [[ "$code" == "201" || "$code" == "200" ]] || warn "add public-keys variable -> HTTP $code"
}

# ---------- 4) Set authenticator scalar config -------------------------------
set_authenticator_vars() {
  local issuer="$JENKINS_LOCAL_BASE_URL"   # must equal JWT iss claim (no trailing slash)
  log "Setting issuer=$issuer audience=$CONJUR_AUDIENCE token-app-property=jenkins_full_name identity-path=data/jenkins-apps"
  conjur_set_var "${AUTHN_BRANCH}/issuer"            "$issuer"              >/dev/null
  conjur_set_var "${AUTHN_BRANCH}/audience"          "$CONJUR_AUDIENCE"     >/dev/null
  conjur_set_var "${AUTHN_BRANCH}/token-app-property" "jenkins_full_name"   >/dev/null
  conjur_set_var "${AUTHN_BRANCH}/identity-path"      "data/jenkins-apps"   >/dev/null
}

# ---------- 5a) Force the Conjur plugin to mint a JWT (populates JWKS) -------
# The plugin generates its in-memory RSA signing key lazily on first JWT request.
# We poke it via the script console so the JWKS endpoint returns a key.
force_jwt_generation() {
  log "Forcing Conjur plugin to mint a JWT (populates /jwtauth/conjur-jwk-set)"
  local jar crumb
  jar=$(mktemp /tmp/jcookies.XXXXXX)
  crumb=$(curl -sS --max-time 5 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" "$JENKINS_LOCAL_BASE_URL/crumbIssuer/api/json" | jq -r .crumb)
  local script
  script='import jenkins.model.Jenkins
def cl = Jenkins.instance.pluginManager.getPlugin("conjur-credentials").classLoader
def jwtCls = cl.loadClass("org.conjur.jenkins.jwtauth.impl.JwtToken")
def cfgCls = cl.loadClass("org.conjur.jenkins.configuration.GlobalConjurConfiguration")
def cfg = cfgCls.getMethod("get").invoke(null)
def jwt = jwtCls.getMethod("getToken", Object.class, cfgCls).invoke(null, Jenkins.instance, cfg)
println("jwt minted, length=" + jwt.length())'
  curl -sS --max-time 10 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" -X POST -H "Jenkins-Crumb: $crumb" \
    --data-urlencode "script=${script}" "$JENKINS_LOCAL_BASE_URL/scriptText" | sed 's/^/  /'
  rm -f "$jar"
}

# ---------- 5b) Sync Jenkins JWKS -> Conjur public-keys ----------------------
sync_public_keys() {
  log "Fetching JWKS from $JENKINS_LOCAL_BASE_URL/jwtauth/conjur-jwk-set"
  local jwks kid payload code
  jwks=$(curl -sS --max-time 5 "$JENKINS_LOCAL_BASE_URL/jwtauth/conjur-jwk-set")
  kid=$(printf '%s' "$jwks" | jq -r '.keys[0].kid // "null"')
  if [[ "$kid" == "null" || -z "$kid" ]]; then
    warn "JWKS still empty after force_jwt_generation. Check Jenkins logs."
    return 1
  fi
  payload=$(printf '%s' "$jwks" | jq -c '{type:"jwks",value:.}')
  code=$(conjur_set_var "${AUTHN_BRANCH}/public-keys" "$payload")
  if [[ "$code" != "201" && "$code" != "200" ]]; then
    err "public-keys set -> HTTP $code"
    return 1
  fi
  log "public-keys synced (kid=$kid, $(printf '%s' "$payload" | wc -c | tr -d ' ') bytes)"
}

# ---------- 6a) PATCH-delete jwks-uri (force public-keys mode) ---------------
remove_jwks_uri() {
  local probe code
  probe=$(conjur_get_var "${AUTHN_BRANCH}/jwks-uri")
  code="${probe%%|*}"
  if [[ "$code" == "404" ]]; then
    log "jwks-uri already absent"
    return 0
  fi
  log "Deleting jwks-uri variable via PATCH (forces Conjur to use public-keys)"
  local rc
  rc=$(conjur_patch_policy "$AUTHN_BRANCH" "- !delete
  record: !variable jwks-uri")
  [[ "$rc" == "201" || "$rc" == "200" ]] || warn "PATCH delete jwks-uri -> HTTP $rc"
}

# ---------- 6b) PATCH-delete public-keys (force jwks-uri mode) ---------------
remove_public_keys() {
  local probe code
  probe=$(conjur_get_var "${AUTHN_BRANCH}/public-keys")
  code="${probe%%|*}"
  if [[ "$code" == "404" ]]; then
    log "public-keys already absent"
    return 0
  fi
  log "Deleting public-keys variable via PATCH (forces Conjur to use jwks-uri)"
  local rc
  rc=$(conjur_patch_policy "$AUTHN_BRANCH" "- !delete
  record: !variable public-keys")
  [[ "$rc" == "201" || "$rc" == "200" ]] || warn "PATCH delete public-keys -> HTTP $rc"
}

# ---------- 6c) Set jwks-uri variable (only used in jwks-uri mode) -----------
ensure_jwks_uri_variable() {
  log "Ensuring 'jwks-uri' variable exists in $AUTHN_BRANCH"
  local code
  code=$(conjur_apply_policy "$AUTHN_BRANCH" "- !variable
  id: jwks-uri")
  [[ "$code" == "201" || "$code" == "200" ]] || warn "add jwks-uri variable -> HTTP $code"
}

set_jwks_uri() {
  local url="$1"
  if [[ -z "$url" ]]; then
    err "JWT_TRUST_MODE=jwks-uri requires JWKS_URL_OVERRIDE or JENKINS_JWKS_URI to be set"
    err "  For Edge mode on Docker Desktop, use:"
    err "    JWKS_URL_OVERRIDE=http://host.docker.internal:${JENKINS_PORT}/jwtauth/conjur-jwk-set"
    exit 1
  fi
  ensure_jwks_uri_variable
  log "Setting jwks-uri = $url"
  conjur_set_var "${AUTHN_BRANCH}/jwks-uri" "$url" >/dev/null
}

# ---------- 7) Authenticator status check ------------------------------------
verify_authenticator_status() {
  # In Edge mode with jwks-uri = http://host.docker.internal:8081/..., the
  # Conjur Cloud SaaS authenticator status endpoint will *always* fail with
  # CONJ00087E "Failed to fetch JWKS ... invalid URI" because SaaS literally
  # cannot resolve host.docker.internal. That hostname is intentionally only
  # reachable from inside the Docker network where Edge runs. Edge does the
  # actual JWT validation. So skip the SaaS-side check in this combination
  # and rely on the sanity build below as ground truth.
  if [[ "$JWT_TRUST_MODE" == "jwks-uri" && "${CONJUR_AUTH_TARGET:-cloud}" == "edge" ]]; then
    log "Authenticator status: skipping SaaS check (Edge mode — JWKS lives on a Docker-network-only hostname)"
    log "                     Edge does validation locally; sanity build below is the ground truth."
    return 0
  fi

  local body code
  body=$(curl -sS --max-time 10 -w '\n__HTTP__%{http_code}' \
    "$SM_BASE/api/authn-jwt/${CONJUR_JWT_AUTHN_ID}/conjur/status" \
    -H "Authorization: Token token=\"${conjur_token}\"")
  code="${body##*__HTTP__}"
  body="${body%$'\n'__HTTP__*}"
  if [[ "$code" == "200" ]]; then
    log "Authenticator status: OK"
  else
    warn "Authenticator status: HTTP $code"
    warn "Body: $body"
  fi
}

# ---------- 8) Create Jenkins ConjurSecretCredentialsImpl entries ------------
create_jenkins_credentials() {
  log "Creating Jenkins ConjurSecretCredentialsImpl entries for SSH user/password"
  local user_var="data/vault/${SAFE_NAME}/account-ssh-user-1/username"
  local pass_var="data/vault/${SAFE_NAME}/account-ssh-user-1/password"

  local script
  script=$(cat <<GROOVY
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.Domain
import org.conjur.jenkins.conjursecrets.ConjurSecretCredentialsImpl

def store = SystemCredentialsProvider.instance.store
def domain = Domain.global()
def specs = [
  ["${user_var}", "Conjur: SSH username"],
  ["${pass_var}", "Conjur: SSH password"]
]
specs.each { sp ->
  def id = sp[0]; def desc = sp[1]
  def existing = store.getCredentials(domain).find { it.id == id }
  if (existing) {
    store.removeCredentials(domain, existing)
    println("REPLACED " + id)
  }
  def cred = new ConjurSecretCredentialsImpl(CredentialsScope.GLOBAL, id, id, desc)
  store.addCredentials(domain, cred)
  println("ADDED    " + id)
}
GROOVY
)
  local jar code
  jar=$(mktemp /tmp/jcookies.XXXXXX)
  local crumb
  crumb=$(curl -sS --max-time 5 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" "$JENKINS_LOCAL_BASE_URL/crumbIssuer/api/json" | jq -r .crumb)
  code=$(curl -sS --max-time 15 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" -X POST -H "Jenkins-Crumb: ${crumb}" \
    --data-urlencode "script=${script}" -w '\n__HTTP__%{http_code}' \
    "$JENKINS_LOCAL_BASE_URL/scriptText") || true
  rm -f "$jar"
  printf '%s\n' "$code" | sed 's/^/  /'
}

# ---------- 9) Push rendered pipeline script to the job ----------------------
push_pipeline_to_job() {
  log "Rendering pipeline (setup/jenkins/pipeline/get_secrets.groovy)"
  bash "$demo_dir/render_pipeline.sh" >/dev/null

  # Copy file into the container so Groovy reads it byte-for-byte (no escaping).
  docker cp "$JENKINS_PIPELINE_FILE" "${JENKINS_CONTAINER}:/var/jenkins_home/get_secrets.groovy" >/dev/null
  log "Pipeline copied into container at /var/jenkins_home/get_secrets.groovy"

  local script
  script='import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition
def job = Jenkins.instance.getItem("global-credentials-demo")
if (job == null) { println("NO_JOB"); return }
def f = new File(Jenkins.instance.rootDir, "get_secrets.groovy")
if (!f.exists()) { println("NO_FILE " + f); return }
def newScript = f.text
job.definition = new CpsFlowDefinition(newScript, true)
job.save()
println("UPDATED job global-credentials-demo (script " + newScript.length() + " bytes)")'
  local jar crumb code
  jar=$(mktemp /tmp/jcookies.XXXXXX)
  crumb=$(curl -sS --max-time 5 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" "$JENKINS_LOCAL_BASE_URL/crumbIssuer/api/json" | jq -r .crumb)
  code=$(curl -sS --max-time 15 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" -X POST -H "Jenkins-Crumb: ${crumb}" \
    --data-urlencode "script=${script}" \
    "$JENKINS_LOCAL_BASE_URL/scriptText") || true
  rm -f "$jar"
  printf '%s\n' "$code" | sed 's/^/  /'
}

# ---------- 10) Trigger a sanity build ---------------------------------------
last_build_number() {
  curl -sS --max-time 5 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    "$JENKINS_LOCAL_BASE_URL/job/global-credentials-demo/api/json" \
    | jq -r '.lastBuild.number // 0'
}

build_result() {
  curl -sS --max-time 5 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    "$JENKINS_LOCAL_BASE_URL/job/global-credentials-demo/$1/api/json" \
    | jq -r '.result // "null"'
}

trigger_sanity_build() {
  if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
    log "SKIP_BUILD=1 -> skipping sanity build"
    return 0
  fi
  log "Triggering sanity build of global-credentials-demo"
  local pre_last
  pre_last=$(last_build_number)
  local jar crumb code
  jar=$(mktemp /tmp/jcookies.XXXXXX)
  crumb=$(curl -sS --max-time 5 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" "$JENKINS_LOCAL_BASE_URL/crumbIssuer/api/json" | jq -r .crumb)
  code=$(curl -sS --max-time 5 -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$jar" -b "$jar" -X POST -H "Jenkins-Crumb: ${crumb}" -o /dev/null -w '%{http_code}' \
    "$JENKINS_LOCAL_BASE_URL/job/global-credentials-demo/build")
  rm -f "$jar"
  if [[ "$code" != "201" ]]; then
    warn "Build trigger returned HTTP $code"
    return 1
  fi

  log "Waiting up to 40s for a NEW build (#>$pre_last) to complete..."
  local last result
  last="$pre_last"; result="null"
  for _ in $(seq 1 20); do
    sleep 2
    last=$(last_build_number)
    if [[ "$last" -gt "$pre_last" ]]; then
      result=$(build_result "$last")
      [[ "$result" != "null" ]] && break
    fi
  done
  log "Build #${last}: ${result}"

  if docker exec "$JENKINS_CONTAINER" test -f /var/jenkins_home/workspace/global-credentials-demo/demo.txt 2>/dev/null; then
    log "demo.txt (last 2 lines, secret lengths only):"
    docker exec "$JENKINS_CONTAINER" bash -c '
      tail -2 /var/jenkins_home/workspace/global-credentials-demo/demo.txt | while IFS= read -r line; do
        key="${line%%=*}"; val="${line#*=}"
        printf "  %s=(len=%d)\n" "$key" "${#val}"
      done' 2>/dev/null
  fi

  [[ "$result" == "SUCCESS" ]]
}

resolve_jwks_url() {
  if [[ -n "${JWKS_URL_OVERRIDE:-}" ]]; then
    printf '%s' "$JWKS_URL_OVERRIDE"
    return
  fi
  if [[ "${CONJUR_AUTH_TARGET:-cloud}" == "edge" ]]; then
    # Edge runs on this Docker host, so it reaches Jenkins via host.docker.internal.
    printf 'http://host.docker.internal:%s/jwtauth/conjur-jwk-set' "${JENKINS_PORT:-8081}"
    return
  fi
  printf '%s' "${JENKINS_JWKS_URI:-}"
}

apply_jwt_trust_mode() {
  case "$JWT_TRUST_MODE" in
    public-keys)
      ensure_public_keys_variable
      remove_jwks_uri
      # Push Jenkins-side state BEFORE syncing JWKS so the verification build
      # has the right credentials + pipeline to use.
      create_jenkins_credentials
      push_pipeline_to_job
      force_jwt_generation
      if ! sync_public_keys; then
        err "Could not sync JWKS to Conjur. See above warnings."
        exit 1
      fi
      ;;
    jwks-uri)
      local url
      url=$(resolve_jwks_url)
      log "JWT trust mode: jwks-uri (Conjur fetches JWKS at $url)"
      ensure_jwks_uri_variable
      set_jwks_uri "$url"
      remove_public_keys
      create_jenkins_credentials
      push_pipeline_to_job
      # Even in jwks-uri mode we force JWT generation so the plugin materializes
      # its in-memory key. Edge will fetch it on the next auth request.
      force_jwt_generation
      ;;
  esac
}

# ---------- main -------------------------------------------------------------
main() {
  log "Demo dir: $demo_dir"
  log "Authenticator branch: $AUTHN_BRANCH  (audience=$CONJUR_AUDIENCE)"
  log "Jenkins: $JENKINS_LOCAL_BASE_URL  (admin=${JENKINS_ADMIN_USER})"
  log "JWT trust mode: $JWT_TRUST_MODE   |   Conjur auth target: ${CONJUR_AUTH_TARGET:-cloud}"

  require_jenkins_running
  verify_jenkins_admin
  get_tokens

  run_base_setup_if_requested
  apply_policies
  set_authenticator_vars

  apply_jwt_trust_mode

  verify_authenticator_status
  if trigger_sanity_build; then
    log "End-to-end verified: secrets retrieved via Conjur JWT auth ($JWT_TRUST_MODE / ${CONJUR_AUTH_TARGET:-cloud})."
  else
    warn "Sanity build did not SUCCEED. Inspect: $JENKINS_LOCAL_BASE_URL/job/global-credentials-demo/"
  fi

  log "Done."
  log "Next: bash ready_check.sh  (or bash demo.sh to run the interactive walkthrough)"
}

main "$@"
