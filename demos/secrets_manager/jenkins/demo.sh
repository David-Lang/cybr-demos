#!/bin/bash
# Jenkins + CyberArk Secrets Manager (JWT) — interactive demo (~25-30 min with UI).
#
# Tells the full story standalone:
#   why JWT auth, how Conjur policy maps Jenkins to a workload identity,
#   how secrets land in a pipeline as masked credentials, and how rotation
#   propagates from Privilege Cloud to a running build.
#
# Mode-aware: when CONJUR_AUTH_TARGET=edge, weaves the Conjur Cloud Edge
# story (local Edge container, replication from SaaS, in-network JWT auth)
# through every step. When CONJUR_AUTH_TARGET=cloud (default), narrates the
# direct-to-SaaS path with public-keys signature trust.
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/jenkins_demo_lib.sh"
jenkins_demo_init

POLL_INTERVAL="${CYBR_JENKINS_DEMO_POLL_INTERVAL:-15}"
MAX_ROTATION_POLLS=12
JOB_NAME="global-credentials-demo"

if [ ! -f "$JENKINS_VARS_FILE" ]; then
  printf "${RED}Missing %s — run: cp setup/vars.env.example setup/vars.env${NC}\n" "$JENKINS_VARS_FILE"
  exit 1
fi

jenkins_load_env

AUTHN_ID="${CONJUR_JWT_AUTHN_ID:-jenkins1}"
CLOUD_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
SECRET_USER_PATH="data/vault/${SAFE_NAME}/account-ssh-user-1/username"
SECRET_PASS_PATH="data/vault/${SAFE_NAME}/account-ssh-user-1/password"
JENKINS_CONTAINER="${JENKINS_CONTAINER:-cybr-jenkins}"
JENKINS_UI_URL="${JENKINS_LOCAL_URL:-http://127.0.0.1:${JENKINS_PORT:-8081}}"

# Mode toggles — drive narrative, header text, and which container/URL we show.
AUTH_TARGET="${CONJUR_AUTH_TARGET:-cloud}"
TRUST_MODE="${JWT_TRUST_MODE:-public-keys}"
EDGE_CONTAINER="${EDGE_CONTAINER:-cybr_conjur_edge}"
EDGE_HOST="${EDGE_HOST:-host.docker.internal}"
EDGE_PORT="${EDGE_PORT:-443}"
EDGE_HEALTH_PORT="${EDGE_HEALTH_PORT:-444}"

case "$AUTH_TARGET" in
  edge)
    APPLIANCE_URL="https://${EDGE_HOST}:${EDGE_PORT}/api"
    APPLIANCE_LABEL="Conjur Cloud Edge (local container)"
    ;;
  *)
    APPLIANCE_URL="$CLOUD_URL"
    APPLIANCE_LABEL="Conjur Cloud SaaS"
    ;;
esac

AUTOMATED=0
if jenkins_automation_ready 2>/dev/null; then
  AUTOMATED=1
fi

pause() {
  printf "\n${YELLOW}    ▶ Press ENTER to continue...${NC}"
  read -r
  echo
}

header() {
  local step="$1"
  local title="$2"
  printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${BOLD}  %s  %s${NC}\n" "$step" "$title"
  printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

run_cmd() {
  printf "    ${GREEN}\$ %s${NC}\n" "$*"
  "$@" 2>&1 | while IFS= read -r line; do printf "    %s\n" "$line"; done
}

status_ok() { printf "    ${GREEN}  ✔  %s${NC}\n" "$1"; }
status_warn() { printf "    ${YELLOW}  ⚠  %s${NC}\n" "$1"; }
status_fail() { printf "${RED}  ✘  %s${NC}\n" "$1"; }

gui_break() {
  local title="$1"
  shift
  printf "\n${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}\n"
  printf "${YELLOW}║  JENKINS UI — %-44s ║${NC}\n" "$title"
  printf "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}\n"
  while [ $# -gt 0 ]; do
    printf "    %s\n" "$1"
    shift
  done
  printf "\n${YELLOW}    ▶ Complete the UI steps above, then press ENTER...${NC}\n"
  read -r
  echo
}

get_conjur_secret_value() {
  local conjur_token="$1"
  local variable_path="$2"
  curl -sf \
    -H "Authorization: Token token=\"${conjur_token}\"" \
    "https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/${variable_path}" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════
header "Intro" "Jenkins + CyberArk Secrets Manager (JWT)"
if [[ "$AUTH_TARGET" == "edge" ]]; then
  cat <<INTRO

  The problem:
    Jenkins pipelines need credentials to do their jobs — SSH keys,
    cloud creds, registry tokens, database passwords. Hardcoding them
    in Jenkinsfiles or static credential stores is a known liability:
    they leak, they don't rotate, and they outlive the people who set
    them up.

  The flow we are about to walk:

    Privilege Cloud Safe ─> Conjur Cloud SaaS ─> Conjur Cloud Edge
                                                       |
                                                       v
                                Jenkins pipeline <─ JWT auth + secret read

  What is happening at each hop:
    * Privilege Cloud   — the source of record for the credential
    * Conjur Cloud SaaS — central policy + secret distribution layer
    * Conjur Cloud Edge — a CyberArk-managed container running ALONGSIDE
                          Jenkins on the same Docker host. It replicates
                          policy and secrets from the SaaS over an
                          outbound-only TLS connection, then validates
                          Jenkins JWTs and serves secrets locally.
    * Jenkins plugin    — mints a short-lived JSON Web Token, calls
                          Edge over HTTPS, gets a Conjur access token,
                          fetches secrets, injects them as masked env
                          vars in the pipeline. No static API key.

  Why Edge is in this demo:
    Customers with strict outbound network policies, low-latency build
    farms, or regulatory boundaries cannot have every Jenkins build
    round-tripping to a public SaaS endpoint. Edge keeps the
    auth + secret-read path entirely inside the Docker host while still
    benefiting from SaaS-managed policy.

INTRO
else
  cat <<INTRO

  The problem:
    Jenkins pipelines need credentials to do their jobs — SSH keys,
    cloud creds, registry tokens, database passwords. Hardcoding them
    in Jenkinsfiles or static credential stores is a known liability:
    they leak, they don't rotate, and they outlive the people who set
    them up.

  The flow we are about to walk:

    Privilege Cloud Safe ─> Conjur Cloud SaaS ─> Jenkins pipeline
                                  ^                       |
                                  +────────── JWT auth ───+

  What is happening at each hop:
    * Privilege Cloud   — the source of record for the credential
    * Conjur Cloud SaaS — central policy + secret distribution layer.
                          Validates Jenkins JWTs against a public-keys
                          variable that mirrors Jenkins's signing keys.
    * Jenkins plugin    — mints a short-lived JSON Web Token, calls
                          Conjur Cloud, gets an access token, fetches
                          secrets, injects them as masked env vars in
                          the pipeline. No static API key.

INTRO
fi
if [[ "$AUTOMATED" -eq 1 ]]; then
  status_ok "go.sh automation detected (plugin + job ${JOB_NAME})"
else
  status_warn "Full automation not detected — run: bash go.sh"
fi
pause

# ═══════════════════════════════════════════════════════════
header "1/11" "Demo configuration"
printf "\n    ${BOLD}Tenant + demo variables:${NC}\n\n"
printf "    SAFE_NAME:            %s\n" "$SAFE_NAME"
printf "    JWT_CLAIM_IDENTITY:   %s\n" "$JWT_CLAIM_IDENTITY"
printf "    CONJUR_JWT_AUTHN_ID:  %s\n" "$AUTHN_ID"
printf "    TENANT_SUBDOMAIN:     %s\n" "$TENANT_SUBDOMAIN"
printf "    JENKINS_UI:           %s\n" "$JENKINS_UI_URL"
printf "\n    ${BOLD}Architecture toggles:${NC}\n\n"
printf "    CONJUR_AUTH_TARGET:   %s   (%s)\n" "$AUTH_TARGET" "$APPLIANCE_LABEL"
printf "    JWT_TRUST_MODE:       %s\n" "$TRUST_MODE"
case "$AUTH_TARGET-$TRUST_MODE" in
  edge-jwks-uri)
    printf "    ↳ Plugin appliance:   %s\n" "$APPLIANCE_URL"
    printf "    ↳ Edge container:     %s (HTTPS on host:%s, /health on host:%s)\n" \
      "$EDGE_CONTAINER" "$EDGE_PORT" "$EDGE_HEALTH_PORT"
    printf "    ↳ Edge pulls JWKS at: http://%s:%s/jwtauth/conjur-jwk-set\n" \
      "$EDGE_HOST" "${JENKINS_PORT:-8081}"
    ;;
  cloud-public-keys)
    printf "    ↳ Plugin appliance:   %s\n" "$APPLIANCE_URL"
    printf "    ↳ Conjur trusts JWTs against a JWKS mirrored into the\n"
    printf "      authn-jwt 'public-keys' variable (no inbound to Jenkins).\n"
    ;;
  *)
    printf "    ↳ Plugin appliance:   %s\n" "$APPLIANCE_URL"
    ;;
esac
if ! cyberark_creds_configured; then
  status_warn "Create demos/tenant_vars.local.sh and run bash go.sh before live build"
fi
printf "\n    ${BOLD}Conjur variable paths the pipeline will read:${NC}\n"
printf "      %s\n      %s\n" "$SECRET_USER_PATH" "$SECRET_PASS_PATH"
pause

# ═══════════════════════════════════════════════════════════
if [[ "$AUTH_TARGET" == "edge" ]]; then
  header "2/11" "Infrastructure — Jenkins + Conjur Cloud Edge (Docker)"
  cat <<'TALK'

  Two containers on the same Docker host. Jenkins is the consumer.
  Edge is a CyberArk-managed container that replicates from Conjur
  Cloud SaaS over outbound TLS, then validates JWTs and serves
  secrets locally — no inbound network reach from SaaS to either
  container is required.

TALK
  run_cmd docker ps -a --filter "name=${JENKINS_CONTAINER}" --filter "name=${EDGE_CONTAINER}"
  if jenkins_container_running; then
    status_ok "Jenkins container is running"
  else
    status_warn "Jenkins container not running — run: bash go.sh"
  fi
  if edge_container_running; then
    status_ok "Edge container is running"
  else
    status_warn "Edge container not running — run: bash setup/edge/setup.sh"
  fi
  if edge_health_ok; then
    status_ok "Edge /health responding (host port ${EDGE_HEALTH_PORT})"
  else
    status_warn "Edge /health not responding — replication may not be complete"
  fi
  printf "\n    ${BOLD}Edge replicating policy + secrets from SaaS (last few log lines):${NC}\n"
  run_cmd bash -c "docker logs --tail 80 ${EDGE_CONTAINER} 2>&1 | grep -iE 'replication|replicated' | tail -5"
else
  header "2/11" "Infrastructure — Jenkins (Docker)"
  cat <<'TALK'

  Jenkins runs as a single Docker container. The Conjur Secrets
  plugin is installed and configured to talk to Conjur Cloud SaaS.
  No public Jenkins URL is required — Conjur trusts JWT signatures
  via a 'public-keys' variable that mirrors Jenkins's signing keys.

TALK
  run_cmd docker ps -a --filter "name=${JENKINS_CONTAINER}"
  if jenkins_container_running; then
    status_ok "Jenkins container is running"
  else
    status_warn "Jenkins container not running — run: bash go.sh"
  fi
fi
pause

# ═══════════════════════════════════════════════════════════
header "3/11" "JWT authenticator — how Jenkins proves who it is"
cat <<TALK

  Every build, the Conjur Secrets plugin signs a short-lived JSON Web
  Token with a private key it generates in memory, and POSTs it to
  authn-jwt/${AUTHN_ID}. The receiver validates the signature, reads
  the claims, looks up the corresponding workload host in Conjur
  policy, and issues a Conjur access token in return. That token is
  then used to fetch the actual secret values.

  Two things make this safe:
    1. The JWT lives ~minutes, not forever. Stolen tokens expire fast.
    2. Conjur policy decides what the token can access — Jenkins gets
       only the safe paths granted to its workload host.

TALK
printf "    ${BOLD}Authenticator policy (jwt_service_jenkins.tmpl.yaml):${NC}\n"
run_cmd sed -n '1,50p' "$JENKINS_DEMO_DIR/setup/conjur/jwt_service_jenkins.tmpl.yaml"
printf "\n    ${BOLD}Plugin global settings (Manage Jenkins -> System):${NC}\n"
printf "      Appliance URL:        %s\n" "$APPLIANCE_URL"
printf "      Service ID:           authn-jwt/%s\n" "$AUTHN_ID"
printf "      Audience:             %s\n" "${CONJUR_AUDIENCE:-cyberark-conjur}"
printf "      token-app-property:   jenkins_full_name\n"
if [[ "$AUTH_TARGET" == "edge" ]]; then
  cat <<'TALK'

    Notice the appliance URL: it is NOT a public SaaS endpoint. It
    points at the Edge container running on this Docker host. The
    auth path never leaves the host. Edge talked to Conjur Cloud
    SaaS exactly once, on its own startup, to replicate policy.

TALK
fi
pause

# ═══════════════════════════════════════════════════════════
header "4/11" "Workload identity — jenkins_full_name claim"
cat <<TALK

  The Jenkins plugin embeds the pipeline job's full name into the JWT
  as the 'jenkins_full_name' claim. The authenticator is configured
  to use that claim as the identity token-app-property, mapped under:

    data/jenkins-apps/${JWT_CLAIM_IDENTITY}

  In other words: each Jenkins job IS a Conjur workload identity.
  No shared service account, no static credential.

  Default GlobalCredentials = identity for a root-level pipeline job.
  Folder-scoped pipelines would use 'folder/job' style claims and map
  to dedicated host policy.

TALK
run_cmd sed -n '1,20p' "$JENKINS_DEMO_DIR/setup/conjur/workload1.tmpl.yaml"
printf "\n    ${BOLD}Rendered host id:${NC} data/jenkins-apps/%s\n" "$JWT_CLAIM_IDENTITY"
pause

# ═══════════════════════════════════════════════════════════
header "5/11" "Conjur policy — identity and safe access"
cat <<TALK

  Five policy files wire authorization. Each one is small, declarative,
  and applied via the Conjur policy API by setup/conjur/setup.sh:

    1. authenticator_consumers   — org may use authn-jwt at all
    2. jwt_service_jenkins        — declares authn-jwt/${AUTHN_ID}
                                    + the public-keys / jwks-uri /
                                    issuer / audience variables
    3. workload1                  — Jenkins workload host with JWT
                                    annotations (jenkins_full_name)
    4. jenkins_apps_vault_grant   — host may READ synced safe secrets
    5. jenkins_jwt_apps_grant     — host may AUTHENTICATE via authn-jwt

  Policy is the single source of truth for who can do what. Pull
  one of these files out of Conjur and the build immediately stops
  retrieving secrets.

TALK
for f in authenticator_consumers.yaml jwt_service_jenkins.tmpl.yaml \
  workload1.tmpl.yaml jenkins_apps_vault_grant.tmpl.yaml \
  jenkins_jwt_apps_grant.tmpl.yaml; do
  printf "\n    ${BOLD}-- %s --${NC}\n" "$f"
  run_cmd sed -n '1,25p' "$JENKINS_DEMO_DIR/setup/conjur/$f"
done
if [ -f "$JENKINS_DEMO_DIR/setup/conjur/workload1.yaml" ]; then
  printf "\n    ${BOLD}Rendered workload1.yaml (applied):${NC}\n"
  run_cmd sed -n '1,20p' "$JENKINS_DEMO_DIR/setup/conjur/workload1.yaml"
fi
pause

# ═══════════════════════════════════════════════════════════
header "6/11" "Live connectivity — JWT signature trust"
if curl -sf --connect-timeout 5 "${JENKINS_UI_URL}/login" >/dev/null; then
  status_ok "Jenkins UI reachable: ${JENKINS_UI_URL}"
else
  status_warn "Jenkins UI not reachable at ${JENKINS_UI_URL}"
fi

if [[ "$AUTH_TARGET" == "edge" ]]; then
  cat <<TALK

  In Edge mode, signature trust is configured via the 'jwks-uri'
  authn variable, which Conjur policy stores as:

    http://${EDGE_HOST}:${JENKINS_PORT:-8081}/jwtauth/conjur-jwk-set

  That is a Docker-network-only hostname. The SaaS endpoint cannot
  reach it. Edge can — and Edge is the one doing JWT validation.

  Trust chain at runtime:
    1. Edge sees an authn-jwt request
    2. Edge HTTP-GETs the JWKS URL above to learn Jenkins's public keys
    3. Edge verifies the JWT signature using those keys
    4. Edge looks up the workload host (replicated from SaaS policy)
    5. Edge issues a short-lived Conjur access token

TALK
  printf "    ${BOLD}Edge cert (auto-generated, served on host port %s):${NC}\n" "$EDGE_PORT"
  run_cmd bash -c "echo | openssl s_client -connect 127.0.0.1:${EDGE_PORT} 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null"
  printf "\n    ${BOLD}Local JWKS (what Edge fetches at every authn-jwt request):${NC}\n"
  if curl -sf --connect-timeout 5 "${JENKINS_UI_URL}/jwtauth/conjur-jwk-set" >/dev/null 2>&1; then
    run_cmd bash -c "curl -sf --connect-timeout 5 \"${JENKINS_UI_URL}/jwtauth/conjur-jwk-set\" | jq -c '.keys[0] | {kid, kty, alg}'"
    status_ok "JWKS endpoint up — Edge can fetch Jenkins's signing keys"
  else
    status_warn "JWKS endpoint not responding — run: bash finish_setup.sh"
  fi
else
  cat <<'TALK'

  In default cloud mode, signature trust is established by mirroring
  Jenkins's JWKS into the Conjur 'public-keys' authn variable.
  finish_setup.sh did this. Conjur Cloud verifies every JWT against
  the mirrored copy in-process — no outbound HTTP call to Jenkins.

  This means Conjur Cloud SaaS does NOT need any inbound network
  reach back to Jenkins. The trade-off: every Jenkins restart
  rotates the in-memory key, so finish_setup.sh re-syncs.

TALK
  if curl -sf --connect-timeout 5 "${JENKINS_UI_URL}/jwtauth/conjur-jwk-set" >/dev/null 2>&1; then
    printf "    ${BOLD}Local JWKS (mirrored into the Conjur public-keys variable):${NC}\n"
    run_cmd bash -c "curl -sf --connect-timeout 5 \"${JENKINS_UI_URL}/jwtauth/conjur-jwk-set\" | jq -c '.keys[0] | {kid, kty, alg}'"
    status_ok "JWKS rendered locally — Conjur verifies against the mirrored copy"
  fi
fi
pause

# ═══════════════════════════════════════════════════════════
header "7/11" "Pipeline — what to fetch"
cat <<'TALK'

  The pipeline declares 'conjurSecretCredential' bindings — one per
  Conjur variable it reads. The binding gives the value an env-var
  alias inside the build (here: SSH_UNAME, SSH_PWD). The plugin
  resolves these at build time, masks them in console output, and
  removes them from the environment when the step exits.

  No API key, no service account password, no cleartext secret in
  Jenkinsfile or job config.

TALK
if pipeline_is_rendered; then
  run_cmd sed -n '1,25p' "$JENKINS_PIPELINE_FILE"
else
  status_warn "Run bash go.sh to render setup/jenkins/pipeline/get_secrets.groovy"
fi
pause

if [[ "$AUTOMATED" -eq 1 ]]; then
  header "8/11" "Jenkins UI — verify automation"
  if [[ "$AUTH_TARGET" == "edge" ]]; then
    gui_break "Verify go.sh automation (Edge mode)" \
      "Open: ${JENKINS_UI_URL}" \
      "1. Manage Jenkins -> System -> Conjur config" \
      "   Appliance URL = ${APPLIANCE_URL}   <-- Edge, NOT SaaS" \
      "   Service ID    = authn-jwt/${AUTHN_ID}" \
      "2. JWT Token Claims -> jenkins_full_name = ${JWT_CLAIM_IDENTITY}" \
      "3. Open the pipeline: ${JENKINS_UI_URL}/job/${JOB_NAME}/" \
      "4. Build Now -> Console Output -> masked SSH_UNAME / SSH_PWD" \
      "5. Workspace artifact demo.txt -> values still masked"
  else
    gui_break "Verify go.sh automation (cloud mode)" \
      "Open: ${JENKINS_UI_URL}" \
      "1. Manage Jenkins -> System -> Conjur config" \
      "   Appliance URL = ${APPLIANCE_URL}" \
      "   Service ID    = authn-jwt/${AUTHN_ID}" \
      "2. JWT Token Claims -> jenkins_full_name = ${JWT_CLAIM_IDENTITY}" \
      "3. Open the pipeline: ${JENKINS_UI_URL}/job/${JOB_NAME}/" \
      "4. Build Now -> Console Output -> masked SSH_UNAME / SSH_PWD" \
      "5. Workspace artifact demo.txt -> values still masked"
  fi
else
  header "8/11" "Jenkins UI — plugin + pipeline"
  gui_break "Plugin + pipeline setup" \
    "Open: ${JENKINS_UI_URL}" \
    "1. Install Conjur Secrets plugin if missing -> restart" \
    "2. TLS: bash import_sm_cert.sh (or upload PEM in plugin UI)" \
    "3. Manage Jenkins -> System -> JWT config (see demo_validation.md)" \
    "4. New Item -> Pipeline -> ${JOB_NAME} -> paste get_secrets.groovy" \
    "5. Refresh Credential Store -> Build Now"
fi

# ═══════════════════════════════════════════════════════════
header "9/11" "The payoff — secret injection"
cat <<'TALK'

  Successful build proves:
    • JWT authentication (no static Conjur API key in the job)
    • Policy grants only the synced safe paths
    • conjurSecretCredential injects SSH_UNAME / SSH_PWD
    • Values are masked in console output

TALK
printf "    Build URL: ${JENKINS_UI_URL}/job/${JOB_NAME}/\n"
pause

# ═══════════════════════════════════════════════════════════
header "10/11" "Live rotation — Privilege Cloud → Conjur → Jenkins"
if ! pipeline_is_rendered || ! cyberark_creds_configured; then
  status_warn "Skipping rotation poll — run bash go.sh first"
  pause
else
  identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
  conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")
  BEFORE_PASS=$(get_conjur_secret_value "$conjur_token" "$SECRET_PASS_PATH")

  printf "\n    ${BOLD}Current password in Conjur (${SECRET_PASS_PATH}):${NC}\n"
  printf "      %s\n\n" "${BEFORE_PASS:-<unable to read>}"

  if [[ "$AUTH_TARGET" == "edge" ]]; then
    cat <<'TALK'

  Rotation flow with Edge:
    1. Change account-ssh-user-1 password in Privilege Cloud (SAFE_NAME safe)
    2. Conjur Sync replicates to Conjur Cloud SaaS
    3. SaaS pushes the change to Edge (MQTT subscription, near-instant)
    4. Re-run the Jenkins pipeline — plugin fetches the new value
       directly from Edge

  No restart, no human in the loop, no static credential to update
  in any pipeline config.

TALK
  else
    cat <<'TALK'

  Rotation flow:
    1. Change account-ssh-user-1 password in Privilege Cloud (SAFE_NAME safe)
    2. Conjur Sync replicates to Conjur Cloud
    3. Re-run the Jenkins pipeline — plugin fetches the new value

  No restart, no human in the loop, no static credential to update
  in any pipeline config.

TALK
  fi

  printf "${YELLOW}    ▶ Change the password in Privilege Cloud, then press ENTER to watch Conjur...${NC}\n"
  read -r

  printf "\n    ${BOLD}Watching Conjur variable for rotation...${NC}\n\n"
  POLL_COUNT=0
  ROTATED=0
  while [ "$POLL_COUNT" -lt "$MAX_ROTATION_POLLS" ]; do
    conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")
    CURRENT_PASS=$(get_conjur_secret_value "$conjur_token" "$SECRET_PASS_PATH")
    POLL_COUNT=$((POLL_COUNT + 1))
    TIMESTAMP=$(date +"%H:%M:%S")

    if [ -n "$BEFORE_PASS" ] && [ -n "$CURRENT_PASS" ] && [ "$CURRENT_PASS" != "$BEFORE_PASS" ]; then
      printf "    ${GREEN}[%s]  ✔  CONJUR ROTATED${NC}\n" "$TIMESTAMP"
      printf "\n    ${BOLD}Before:${NC} %s\n" "$BEFORE_PASS"
      printf "    ${BOLD}After:${NC}  %s\n" "$CURRENT_PASS"
      ROTATED=1
      break
    fi

    REMAINING=$(( (MAX_ROTATION_POLLS - POLL_COUNT) * POLL_INTERVAL ))
    printf "    ${DIM}[%s]${NC}  ◌  polling Conjur... ${DIM}(%d/%d, ~%ds left)${NC}\n" \
      "$TIMESTAMP" "$POLL_COUNT" "$MAX_ROTATION_POLLS" "$REMAINING"
    sleep "$POLL_INTERVAL"
  done

  if [ "$ROTATED" -eq 0 ]; then
    status_fail "Timed out waiting for Conjur password change"
  else
    status_ok "Conjur variable updated"
    gui_break "Re-run pipeline" \
      "1. ${JENKINS_UI_URL}/job/${JOB_NAME}/ → Build Now" \
      "2. Console shows new masked values; demo.txt updated"
  fi
fi

# ═══════════════════════════════════════════════════════════
header "11/11" "Demo complete"
if [[ "$AUTH_TARGET" == "edge" ]]; then
  cat <<SUMMARY

  What we demonstrated:
    [x] Two containers on one Docker host: Jenkins + Conjur Cloud Edge
    [x] Edge replicating policy + secrets from Conjur Cloud SaaS
        over outbound-only TLS — no inbound rules from CyberArk to here
    [x] JWT auth path: Jenkins -> Edge -> in-network JWKS lookup
        Plugin appliance URL never points at the public internet
    [x] authn-jwt/${AUTHN_ID} + 5 Conjur policy files = identity & access
    [x] Workload host data/jenkins-apps/${JWT_CLAIM_IDENTITY} maps the
        pipeline job name to its own Conjur identity
    [x] Pipeline conjurSecretCredential -> masked env vars in build
    [x] Live rotation: Privilege Cloud -> SaaS -> Edge -> next build

  Customer takeaway:
    Conjur Cloud Edge lets restricted-egress, latency-sensitive, or
    regulated environments use the same SaaS-managed identity model
    as everyone else, without their build traffic ever leaving the
    secure network boundary.

SUMMARY
else
  cat <<SUMMARY

  What we demonstrated:
    [x] Docker Jenkins talking directly to Conjur Cloud SaaS
    [x] JWT signature trust via mirrored 'public-keys' (no inbound
        network reach from SaaS to Jenkins required)
    [x] authn-jwt/${AUTHN_ID} + 5 Conjur policy files = identity & access
    [x] Workload host data/jenkins-apps/${JWT_CLAIM_IDENTITY} maps the
        pipeline job name to its own Conjur identity
    [x] Conjur Secrets plugin — JWT-based, no API key in the job
    [x] Pipeline conjurSecretCredential -> masked env vars in build
    [x] Live rotation: Privilege Cloud -> Conjur -> next build

  Customer takeaway:
    Pipelines retrieve credentials at run time from a centrally
    managed source of truth, scoped per-job by Conjur policy. No
    static API keys live in Jenkins. Rotation in Privilege Cloud
    is picked up automatically on the next build.

SUMMARY
fi

printf "\n${BOLD}Open Jenkins? [Y/n]${NC} "
read -r open_jenkins
if [[ "${open_jenkins:-Y}" =~ ^[yY] ]]; then
  if command -v open >/dev/null 2>&1; then
    open "${JENKINS_UI_URL}/job/${JOB_NAME}/"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${JENKINS_UI_URL}/job/${JOB_NAME}/"
  else
    printf "  %s/job/%s/\n" "$JENKINS_UI_URL" "$JOB_NAME"
  fi
fi
printf "\n"
