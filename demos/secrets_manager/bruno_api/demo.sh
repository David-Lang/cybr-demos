#!/bin/bash
# shellcheck disable=SC2059
# Runs the "ALM API Key Auth" Demo App section via the Bruno CLI and narrates
# each step: the application workload authenticates to Secrets Manager with its
# API key (getting a short-lived Conjur session token), then retrieves secrets
# over the REST API. Assumes setup.sh has already run.
set -euo pipefail

# Locate the repo root from this script if the lab bootstrap hasn't exported it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CYBR_DEMOS_PATH:=$(cd "$SCRIPT_DIR/../../.." && pwd)}"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/bruno_api"
ENV_NAME="cybr.secret"
WORK_DIR="$demo_path/.collection"
COLLECTION_DIR="$WORK_DIR/collection"
ENV_FILE="$COLLECTION_DIR/environments/$ENV_NAME.bru"
DEMO_FOLDER="Use Cases/ALM API Key Auth/2 Demo App"
REPORT_FILE="$demo_path/demo.report.json"

hr()  { printf '%s\n' "------------------------------------------------------------"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Read a non-secret value out of the generated Bruno env (<key>: <value>).
envval() {
  grep -E "^[[:space:]]*$1:" "$ENV_FILE" | head -1 | sed -E "s/^[[:space:]]*$1:[[:space:]]*//" | tr -d '\r'
}

preflight() {
  command -v bru >/dev/null 2>&1 || { printf "ERROR: bru CLI not found. Run setup.sh first.\n" >&2; exit 1; }
  [ -f "$COLLECTION_DIR/bruno.json" ] || { printf "ERROR: collection not found. Run setup.sh first.\n" >&2; exit 1; }
  [ -f "$ENV_FILE" ] || { printf "ERROR: Bruno env %s not found. Run setup.sh first.\n" "$ENV_FILE" >&2; exit 1; }
  if ! grep -qE '^[[:space:]]*almAppName_workload_ApiKey:[[:space:]]*\S' "$ENV_FILE"; then
    printf "ERROR: workload API key not present in %s. Re-run setup.sh.\n" "$ENV_FILE" >&2
    exit 1
  fi
}

intro() {
  local app sub acct lab
  app="$(envval UseCaseAlmAppName)"
  sub="$(envval IspSubDomain)"
  acct="$(envval ConjurAccount)"
  lab="$(envval LabId)"

  hr
  printf '\033[1mSecrets Manager — ALM API Key Auth (Demo App)\033[0m\n'
  hr
  printf 'A non-human application workload authenticates to CyberArk Secrets Manager\n'
  printf '(Conjur Cloud) using its own API key, receives a short-lived session token,\n'
  printf 'and uses that token to read secrets over the REST API.\n\n'
  printf '  Tenant subdomain : %s.secretsmgr.cyberark.cloud\n' "$sub"
  printf '  Conjur account   : %s\n' "$acct"
  printf '  Application (app) : %s   (lab %s)\n' "$app" "$lab"
  printf '  Workload identity : host/data/%s/%s-workload\n' "$app" "$app"
  printf '  Workload API key  : present (hidden)\n'

  step "What this demo will do:"
  printf '  1. Authenticate     POST /api/authn/conjur/host%%2Fdata%%2F%s%%2F%s-workload/authenticate\n' "$app" "$app"
  printf '                      (body = workload API key)  ->  Conjur session token\n'
  printf '  2. Retrieve Secret  GET  /api/secrets/conjur/variable/data/vault/%s/account-ssh-user1/password\n' "$app"
  printf '  3. Batch Retrieve   POST /api/secrets/values   (username + address + password in one call)\n'
  printf '  4. List Secrets     GET  /api/resources?kind=variable   (what this workload can see)\n'
}

run_collection() {
  step "Running the requests (Bruno CLI)..."
  hr
  # Runtime session token is set by the Authenticate test and shared across the
  # folder run; a JSON report is written so we can show the responses below.
  ( cd "$COLLECTION_DIR" && bru run "$DEMO_FOLDER" -r --env "$ENV_NAME" --reporter-json "$REPORT_FILE" )
}

render_results() {
  command -v jq >/dev/null 2>&1 || { printf "\n(install jq to see the per-step response detail)\n"; return 0; }
  [ -f "$REPORT_FILE" ] || return 0

  step "What happened (requests + responses):"
  jq -r '
    (if type=="array" then .[0].results else .results end)[]
    | (.test.filename | sub(".*/";"") | sub("\\.bru$";"")) as $name
    | "\n\u25b8 \($name)",
      "    \(.request.method) \(.request.url)",
      "    \u2192 \(.response.status) \(.response.statusText // "")  (\((.response.responseTime // .response.duration // 0))ms)",
      (
        if ($name | test("Authenticate")) then
          "    \u21b3 issued a Conjur session token (base64, \((.response.data|tostring|length)) chars) - used as the bearer token for the reads below"
        elif ($name | test("Retrieve Secret$")) then
          "    \u21b3 password = \(.response.data)"
        elif ($name | test("Batch")) then
          (.response.data.secrets[]? | "    \u21b3 \(.id|sub("^data/vault/[^/]+/";"")) = \(.value)  [\(.status)]")
        elif ($name | test("List")) then
          ("    \u21b3 \((.response.data|length)) variable(s) visible to this workload:"),
          (.response.data[]? | "        - \(.id|sub("^conjur:variable:data/vault/[^/]+/";""))")
        else
          "    \u21b3 \(.response.data|tojson|.[0:200])"
        end
      )
  ' "$REPORT_FILE"
  rm -f "$REPORT_FILE"
}

main() {
  preflight
  intro
  run_collection
  render_results
  step "Demo complete."
  printf 'The workload never used a human credential: it authenticated with its API key,\n'
  printf 'got a short-lived Conjur token, and read only the secrets it is authorized for.\n\n'
}

main "$@"
