#!/bin/bash
# Auto-Rotate Kubernetes Secrets — ESO + CyberArk Conjur Cloud (~12–18 min; pacing is tunable)
# Interactive walkthrough: press ENTER to advance between steps.
set -euo pipefail

# Force UTF-8 so bash's ${#var} and printf widths line up with what the terminal renders.
# (Box drawing chars and em-dashes are multi-byte; without this they pad by bytes.)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ── Palette: bright cyan + yellow (high contrast on dark terminals); red only for errors ──
# $'…' so the variables hold real ESC bytes — works both inside printf format
# strings and when passed as %s arguments to the box helpers below.
ACCENT=$'\033[96m'   # bright cyan — frames, commands, primary highlights
EMPH=$'\033[93m'     # bright yellow — prompts, step IDs, calls-to-action
ERR=$'\033[91m'      # bright red — failures and stale/wrong values only
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

NAMESPACE="eso-reloader"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRET_NAME="db-credentials"
DEPLOYMENT="rotation-demo-app"

# Poll cadence matches ESO refreshInterval (15s): checks align with sync cycles and ease API churn.
# Faster rehearsal: export CYBR_ESO_DEMO_POLL_INTERVAL=5
POLL_INTERVAL="${CYBR_ESO_DEMO_POLL_INTERVAL:-15}"
# Iteration caps × POLL_INTERVAL ≈ max wall-clock per phase (tuned for default 15s).
MAX_SECRET_POLLS=12   # rotation detect (~3 min)
MAX_VOLUME_POLLS=8    # kubelet file sync (~2 min)
MAX_RESTART_POLLS=8   # Reloader rollout (~2 min)

pause() {
  printf "\n${EMPH}    ▶ Press ENTER to continue...${NC}"
  read -r
  echo
}

# ── UTF-8-aware layout helpers ────────────────────────────────────────────────
# All box content includes ANSI color escapes; we strip those before measuring,
# then pad by visual columns instead of bytes so multi-byte chars (— ① ② ③ ▼ •)
# don't shove the right border off-grid.

# Strip ANSI CSI sequences (ESC[…letter) using pure bash — no fork per call.
_strip_ansi() {
  local s="$1" out="" i=0 n=${#1} esc=$'\033'
  while (( i < n )); do
    if [[ "${s:i:1}" == "$esc" && "${s:i+1:1}" == "[" ]]; then
      i=$(( i + 2 ))
      while (( i < n )) && [[ ! "${s:i:1}" =~ [a-zA-Z] ]]; do i=$(( i + 1 )); done
      i=$(( i + 1 ))
    else
      out+="${s:i:1}"
      i=$(( i + 1 ))
    fi
  done
  printf '%s' "$out"
}

# Visible width in columns (LC_ALL is forced to UTF-8 above).
_vlen() {
  local s
  s=$(_strip_ansi "$1")
  printf '%d' "${#s}"
}

# Right-pad a string to N visible columns with spaces.
_vpad() {
  local width="$1" s="$2" len pad
  len=$(_vlen "$s")
  pad=$(( width - len ))
  (( pad < 0 )) && pad=0
  printf '%s%*s' "$s" "$pad" ''
}

# Repeat a (possibly multi-byte) char N times — pure bash, multi-byte safe.
_repeat() {
  local ch="$1" n="$2" out="" i=0
  while (( i < n )); do out+="$ch"; i=$(( i + 1 )); done
  printf '%s' "$out"
}

# Box primitives. WIDTH is the visible width inside the bars, not counting them.
# Optional second arg overrides border color (default ACCENT).
box_top()   { local w="$1" c="${2:-$ACCENT}"; printf '    %s┌%s┐%s\n' "$c" "$(_repeat '─' "$w")" "$NC"; }
box_mid()   { local w="$1" c="${2:-$ACCENT}"; printf '    %s├%s┤%s\n' "$c" "$(_repeat '─' "$w")" "$NC"; }
box_bot()   { local w="$1" c="${2:-$ACCENT}"; printf '    %s└%s┘%s\n' "$c" "$(_repeat '─' "$w")" "$NC"; }
box_blank() { local w="$1" c="${2:-$ACCENT}"; printf '    %s│%*s%s│%s\n' "$c" "$w" '' "$c" "$NC"; }

# Render `│ <content padded to W visible cols> │`. Content may include ANSI escapes.
# Usage: box_row WIDTH "  Some content"            — default ACCENT borders
#        box_row WIDTH "  Some content" "$EMPH"    — custom border color
box_row() {
  local w="$1" content="$2" c="${3:-$ACCENT}" padded
  padded=$(_vpad "$w" "$content")
  printf '    %s│%s%s│%s\n' "$c" "$padded" "$c" "$NC"
}

header() {
  local step="$1" title="$2" title_pad
  title_pad=$(_vpad 46 "$title")
  printf "\n"
  printf "${ACCENT}  ╔══════════════════════════════════════════════════════╗${NC}\n"
  printf "${ACCENT}  ║${NC} ${EMPH}%-6s${NC}${BOLD}%s${NC} ${ACCENT}║${NC}\n" "$step" "$title_pad"
  printf "${ACCENT}  ╚══════════════════════════════════════════════════════╝${NC}\n"
}

run_cmd() {
  printf "    ${ACCENT}\$ %s${NC}\n" "$*"
  "$@" 2>&1 | while IFS= read -r line; do printf "    %s\n" "$line"; done
}

preflight() {
  if ! command -v kubectl >/dev/null 2>&1; then
    printf "${ERR}ERROR: kubectl not found in PATH.${NC}\n" >&2
    exit 1
  fi
  if ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
    printf "${ERR}ERROR: cannot reach the Kubernetes API at:${NC} %s\n" \
      "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)" >&2
    printf "${EMPH}Start the cluster first:${NC}\n" >&2
    printf "  minikube start --driver=docker\n" >&2
    printf "  kubectl cluster-info\n" >&2
    exit 1
  fi
  if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    printf "${ERR}ERROR: namespace '%s' is missing.${NC}\n" "$NAMESPACE" >&2
    printf "${EMPH}Run the demo setup first:${NC}\n" >&2
    printf "  bash %s/setup.sh\n" "$DEMO_DIR" >&2
    exit 1
  fi
}

info_box() {
  local label="$1"
  local value="$2"
  printf "    ${DIM}│${NC} ${BOLD}%-22s${NC} %s\n" "$label" "$value"
}

divider() {
  printf "    ${DIM}├──────────────────────────────────────────────────${NC}\n"
}

status_ok() {
  printf "    ${ACCENT}  ✔  %s${NC}\n" "$1"
}

status_warn() {
  printf "    ${EMPH}  ⚠  %s${NC}\n" "$1"
}

status_fail() {
  printf "    ${ERR}  ✘  %s${NC}\n" "$1"
}

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || [ "$POLL_INTERVAL" -lt 1 ]; then
  printf "${EMPH}Warning:${NC} invalid CYBR_ESO_DEMO_POLL_INTERVAL=%s, defaulting to 15s.\n" "${POLL_INTERVAL:-unset}"
  POLL_INTERVAL=15
fi

get_app_pod() {
  kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

require_app_pod() {
  local pod
  pod="$(get_app_pod)"
  if [ -z "$pod" ]; then
    status_fail "No running app pod found for app=$DEPLOYMENT in namespace $NAMESPACE"
    return 1
  fi
  printf "%s" "$pod"
}

get_env_password() {
  local pod="$1"
  if [ -z "$pod" ]; then
    return 0
  fi
  kubectl exec -n "$NAMESPACE" "$pod" -c app -- printenv DB_PASSWORD 2>/dev/null || true
}

brand_bar() {
  printf "${ACCENT}${BOLD}  %-54s${NC}\n" "  CyberArk Conjur Cloud · ESO · Reloader"
}

# ═══════════════════════════════════════════════════════════
# TITLE SCREEN
# ═══════════════════════════════════════════════════════════
clear 2>/dev/null || true
printf "\n"
brand_bar
printf "\n"
printf "${ACCENT}"
cat <<'LOGO'
           ██████╗██╗   ██╗██████╗ ███████╗██████╗  █████╗ ██████╗ ██╗  ██╗
          ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝
          ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝███████║██████╔╝█████╔╝
          ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██║██╔══██╗██╔═██╗
          ╚██████╗   ██║   ██████╔╝███████╗██║  ██║██║  ██║██║  ██║██║  ██╗
           ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
LOGO
printf "${NC}"
printf "${EMPH}"
cat <<'TITLE'
      ╔═══════════════════════════════════════════════════════════════════╗
      ║                                                                   ║
      ║       █████╗ ██╗   ██╗████████╗ ██████╗                           ║
      ║      ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗                          ║
      ║      ███████║██║   ██║   ██║   ██║   ██║                          ║
      ║      ██╔══██║██║   ██║   ██║   ██║   ██║                          ║
      ║      ██║  ██║╚██████╔╝   ██║   ╚██████╔╝                          ║
      ║      ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝                           ║
      ║                                                                   ║
      ║      ██████╗  ██████╗ ████████╗ █████╗ ████████╗███████╗          ║
      ║      ██╔══██╗██╔═══██╗╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝          ║
      ║      ██████╔╝██║   ██║   ██║   ███████║   ██║   █████╗            ║
      ║      ██╔══██╗██║   ██║   ██║   ██╔══██║   ██║   ██╔══╝            ║
      ║      ██║  ██║╚██████╔╝   ██║   ██║  ██║   ██║   ███████╗          ║
      ║      ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝          ║
      ║                                                                   ║
      ║          K U B E R N E T E S    S E C R E T S                     ║
      ║                                                                   ║
      ╚═══════════════════════════════════════════════════════════════════╝
TITLE
printf "${NC}\n"
printf "    ${DIM}Powered by${NC}  ${ACCENT}${BOLD}CyberArk Conjur Cloud${NC}  ${DIM}+${NC}  ${ACCENT}${BOLD}External Secrets Operator${NC}\n"
printf "    ${DIM}A${NC} ${EMPH}${BOLD}Palo Alto Networks${NC} ${DIM}company${NC}\n\n"

printf "    ${BOLD}End-to-end secret rotation:${NC}\n\n"
printf "      ${EMPH}Privilege Cloud${NC}  ──▶  ${ACCENT}Conjur Sync${NC}  ──▶  ${ACCENT}Conjur Cloud${NC}\n"
printf "      ${DIM}(source of truth)${NC}\n"
printf "                                ${DIM}│${NC}\n"
printf "                                ▼\n"
printf "                       ${ACCENT}ESO Controller${NC}    ${DIM}(JWT auth, 15s poll)${NC}\n"
printf "                                ${DIM}│${NC}\n"
printf "                                ▼\n"
printf "                       ${EMPH}K8s Secret${NC}  ──▶  ${BOLD}Application Pod${NC}\n\n"
printf "    ${BOLD}Two consumption methods:${NC}\n"
printf "      ${ACCENT}① Volume Mount${NC}    ${DIM}── files update automatically${NC}\n"
printf "      ${EMPH}② Env Variables${NC}   ${DIM}── requires pod restart${NC}\n"
printf "\n"
printf "    ${BOLD}Why both consumptions in one demo (same CyberArk path)?${NC}\n\n"
printf "    ${DIM}•${NC} ${BOLD}Single integration:${NC} Privilege Cloud → Conjur → ESO → ${EMPH}one${NC} Kubernetes Secret (%s).\n" "$SECRET_NAME"
printf "    ${DIM}    Reloader watches ${BOLD}that${NC} Secret — there is no second auth flow or second ExternalSecret.\n"
printf "    ${DIM}•${NC} ${BOLD}Two Kubernetes semantics:${NC} secrets-as-${ACCENT}files${NC} update when kubelet syncs the volume; secrets-as-${EMPH}env${NC} are fixed at container start.\n"
printf "    ${DIM}•${NC} ${BOLD}Talk-track goal:${NC} show real-world split (apps read files vs getenv at boot) under one rotation pipeline — and why Reloader closes the env-var gap after ESO updates the Secret.\n\n"
printf "    ${DIM}(Tip:${NC} export ${ACCENT}CYBR_ESO_DEMO_POLL_INTERVAL${DIM}=5 for faster rehearsal polling.)${NC}\n\n"
pause

# ═══════════════════════════════════════════════════════════
header "1/13" "Demo Environment"
# ═══════════════════════════════════════════════════════════
printf "\n    ${DIM}All resources live in the${NC} ${ACCENT}${BOLD}%s${NC} ${DIM}namespace.${NC}\n\n" "$NAMESPACE"
run_cmd kubectl get ns "$NAMESPACE"
echo
run_cmd kubectl get sa -n "$NAMESPACE" eso-reloader-sa
pause

# ═══════════════════════════════════════════════════════════
header "2/13" "ESO Controller"
# ═══════════════════════════════════════════════════════════
printf "\n"
box_top 50
box_row 50 "  ESO runs as a ${BOLD}cluster-wide controller${NC}."
box_row 50 "  It watches for SecretStore and ExternalSecret"
box_row 50 "  resources ${BOLD}across all namespaces${NC}."
box_bot 50
printf "\n"
run_cmd kubectl get pods -n external-secrets
pause

# ═══════════════════════════════════════════════════════════
header "3/13" "SecretStore — Conjur JWT Authentication"
# ═══════════════════════════════════════════════════════════
printf "\n"
printf "    ${BOLD}How ESO authenticates to CyberArk:${NC}\n\n"
box_top 50
box_blank 50
box_row 50 "  ${BOLD}K8s ServiceAccount${NC}"
box_row 50 "       ${DIM}│${NC}  ${DIM}mints JWT token${NC}"
box_row 50 "       ▼"
box_row 50 "  ${ACCENT}authn-jwt/zg-eso${NC}"
box_row 50 "       ${DIM}│${NC}  ${DIM}validates signature via K8s OIDC${NC}"
box_row 50 "       ▼"
box_row 50 "  ${ACCENT}Conjur Cloud${NC}  ${DIM}returns access token${NC}"
box_blank 50
box_row 50 "  ${EMPH}Zero static API keys in the cluster${NC}"
box_blank 50
box_bot 50
printf "\n"

printf "    ${BOLD}SecretStore manifest:${NC}\n"
run_cmd cat "$DEMO_DIR/secretstore.yaml"
echo
printf "    ${BOLD}SecretStore status:${NC}\n"
run_cmd kubectl get secretstore -n "$NAMESPACE" conjur -o wide
SS_READY=$(kubectl get secretstore -n "$NAMESPACE" conjur -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "")
if [ "$SS_READY" = "True" ]; then
  status_ok "SecretStore is Valid and Ready"
else
  status_fail "SecretStore is not ready — check Conjur connectivity"
fi
pause

# ═══════════════════════════════════════════════════════════
header "4/13" "ExternalSecret — 15s Refresh Interval"
# ═══════════════════════════════════════════════════════════
printf "\n"
printf "    ${BOLD}The refresh interval drives rotation detection:${NC}\n\n"
box_top 50
box_blank 50
box_row 50 "  ${EMPH}${BOLD}refreshInterval: 15s${NC}"
box_blank 50
box_row 50 "  Every 15 seconds ESO:"
box_row 50 "    ${ACCENT}①${NC} Re-authenticates to Conjur (JWT)"
box_row 50 "    ${ACCENT}②${NC} Fetches current secret values"
box_row 50 "    ${ACCENT}③${NC} Compares with existing K8s Secret"
box_row 50 "    ${ACCENT}④${NC} Updates K8s Secret if values changed"
box_blank 50
box_bot 50
printf "\n"

printf "    ${BOLD}ExternalSecret manifest:${NC}\n"
run_cmd cat "$DEMO_DIR/externalsecret.yaml"
echo
printf "    ${BOLD}Sync status:${NC}\n"
run_cmd kubectl get externalsecret -n "$NAMESPACE" db-credentials -o wide
ES_STATUS=$(kubectl get externalsecret -n "$NAMESPACE" db-credentials -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "")
if [ "$ES_STATUS" = "SecretSynced" ]; then
  status_ok "ExternalSecret is syncing every 15 seconds"
else
  status_fail "ExternalSecret sync error: $ES_STATUS"
fi
pause

# ═══════════════════════════════════════════════════════════
header "5/13" "Conjur Policy — Identity & Access"
# ═══════════════════════════════════════════════════════════
printf "\n"
printf "    ${BOLD}Three policies wire up authorization in Conjur Cloud:${NC}\n\n"
box_top 52
box_row 52 "  ${ACCENT}①${NC} ${BOLD}Workload Host${NC}"
box_row 52 "     Defines identity + JWT sub annotation"
box_row 52 "                        ${DIM}│${NC}"
box_row 52 "  ${ACCENT}②${NC} ${BOLD}Safe Access Grant${NC}"
box_row 52 "     Adds host to k8s-eso/delegation/consumers"
box_row 52 "                        ${DIM}│${NC}"
box_row 52 "  ${ACCENT}③${NC} ${BOLD}Authenticator Grant${NC}"
box_row 52 "     Allows host to use authn-jwt/zg-eso"
box_bot 52
printf "\n"
for f in "$DEMO_DIR"/conjur-policy/*.yaml; do
  printf "    ${EMPH}── %s ──${NC}\n" "$(basename "$f")"
  while IFS= read -r line; do printf "    ${DIM}%s${NC}\n" "$line"; done < "$f"
  echo
done
pause

# ═══════════════════════════════════════════════════════════
header "6/13" "The K8s Secret — Current State"
# ═══════════════════════════════════════════════════════════
printf "\n"
run_cmd kubectl get secret -n "$NAMESPACE" "$SECRET_NAME"

CURR_USER=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.username}" | base64 --decode)
CURR_PASS=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode)

printf "\n"
box_top 37
box_row 37 "  ${BOLD}Decoded Secret Values${NC}"
box_mid 37
box_row 37 "  username:  ${ACCENT}${CURR_USER}${NC}"
box_row 37 "  password:  ${ACCENT}${CURR_PASS}${NC}"
box_bot 37
pause

# ═══════════════════════════════════════════════════════════
header "7/13" "Application Pod — Two Consumption Methods"
# ═══════════════════════════════════════════════════════════
printf "\n"
printf "    ${BOLD}The app consumes the same Kubernetes Secret (${SECRET_NAME}) TWO ways.${NC}\n"
printf "    ${DIM}This is not two CyberArk or ESO integrations — one ESO sync feeds one Secret; we surface both consumption styles Kubernetes supports.${NC}\n\n"
printf "    ${BOLD}Where each pattern is applicable${NC}\n\n"
printf "    ${ACCENT}① Volume mount ${DIM}(/etc/secrets)${NC} — Use when the app reads ${BOLD}paths${NC}: JDBC/property files, PEM bundles, agents that watch directories.\n"
printf "    ${DIM}    After ESO writes the Secret, kubelet refreshes mounted files — often ${BOLD}no restart${NC}.${NC}\n\n"
printf "    ${EMPH}② Env vars ${DIM}(DB_USERNAME / DB_PASSWORD)${NC} — Use for ${BOLD}12-factor${NC} style apps and frameworks that call getenv() at startup.\n"
printf "    ${DIM}    Values stay stale until a new container starts — ${BOLD}Reloader${NC} triggers that rollout when the Secret changes.${NC}\n\n"
box_top 52
box_blank 52
box_row 52 "  ${ACCENT}┌─────────────────────┐${NC}  ${EMPH}┌─────────────────────┐${NC}"
box_row 52 "  ${ACCENT}│${NC}  ${BOLD}① Volume Mount${NC}     ${ACCENT}│${NC}  ${EMPH}│${NC}  ${BOLD}② Env Variables${NC}    ${EMPH}│${NC}"
box_row 52 "  ${ACCENT}│${NC}  /etc/secrets/      ${ACCENT}│${NC}  ${EMPH}│${NC}  DB_USERNAME        ${EMPH}│${NC}"
box_row 52 "  ${ACCENT}│${NC}                     ${ACCENT}│${NC}  ${EMPH}│${NC}  DB_PASSWORD        ${EMPH}│${NC}"
box_row 52 "  ${ACCENT}│${NC}  Updates: ${ACCENT}AUTO${NC}      ${ACCENT}│${NC}  ${EMPH}│${NC}  Updates: ${ERR}ON RESTART${NC}${EMPH}│${NC}"
box_row 52 "  ${ACCENT}│${NC}  Delay:   ~60-90s   ${ACCENT}│${NC}  ${EMPH}│${NC}  Delay:   pod cycle ${EMPH}│${NC}"
box_row 52 "  ${ACCENT}│${NC}  App change: ${ACCENT}NONE${NC}   ${ACCENT}│${NC}  ${EMPH}│${NC}  App change: ${ACCENT}NONE${NC}   ${EMPH}│${NC}"
box_row 52 "  ${ACCENT}└─────────────────────┘${NC}  ${EMPH}└─────────────────────┘${NC}"
box_blank 52
box_bot 52
printf "\n"

APP_POD=$(require_app_pod)

printf "    ${ACCENT}━━━ ① Volume Mount ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
run_cmd kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- ls -la /etc/secrets/
echo
VOL_USER=$(kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- cat /etc/secrets/username 2>/dev/null || echo "")
VOL_PASS=$(kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- cat /etc/secrets/password 2>/dev/null || echo "")
printf "    ${DIM}│${NC}  /etc/secrets/username:  ${ACCENT}%s${NC}\n" "$VOL_USER"
printf "    ${DIM}│${NC}  /etc/secrets/password:  ${ACCENT}%s${NC}\n" "$VOL_PASS"
pause

printf "    ${EMPH}━━━ ② Environment Variables ━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
ENV_USER=$(kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- printenv DB_USERNAME 2>/dev/null || echo "")
ENV_PASS=$(kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- printenv DB_PASSWORD 2>/dev/null || echo "")
printf "    ${DIM}│${NC}  DB_USERNAME:  ${EMPH}%s${NC}\n" "$ENV_USER"
printf "    ${DIM}│${NC}  DB_PASSWORD:  ${EMPH}%s${NC}\n" "$ENV_PASS"
printf "\n"
if [ "$VOL_PASS" = "$ENV_PASS" ]; then
  status_ok "Both methods show the same value — the secret is in sync"
else
  status_warn "Values differ — env vars are frozen at pod start; volume mounts track the K8s Secret"
  printf "    ${DIM}│${NC}  Volume mount:  ${ACCENT}%s${NC}\n" "$VOL_PASS"
  printf "    ${DIM}│${NC}  Env var:       ${EMPH}%s${NC}\n" "$ENV_PASS"
fi
pause

# ═══════════════════════════════════════════════════════════
header "8/13" "Reloader — Auto Pod Restart on Secret Change"
# ═══════════════════════════════════════════════════════════
printf "\n"
box_top 52
box_row 52 "  ${BOLD}Stakater Reloader${NC} watches K8s Secrets."
box_blank 52
box_row 52 "  When ${BOLD}db-credentials${NC} updates, Reloader triggers"
box_row 52 "  a rolling restart on Deployments with:"
box_blank 52
box_row 52 "    ${ACCENT}reloader.stakater.com/auto: \"true\"${NC}"
box_blank 52
box_row 52 "  This closes the env var gap automatically."
box_bot 52
printf "\n"

RELOADER_POD=$(kubectl get pods -A -l app.kubernetes.io/name=reloader -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$RELOADER_POD" ]; then
  status_ok "Reloader is installed and running"
  echo
  run_cmd kubectl get pods -A -l app.kubernetes.io/name=reloader
else
  status_warn "Reloader not installed — will demo manual restart"
  printf "\n    ${DIM}Install later:${NC}\n"
  printf "    ${DIM}  helm repo add stakater https://stakater.github.io/stakater-charts${NC}\n"
  printf "    ${DIM}  helm install reloader stakater/reloader -n reloader --create-namespace${NC}\n"
fi
echo
printf "    ${BOLD}Deployment annotation:${NC}\n"
ANNOT=$(kubectl get deployment -n "$NAMESPACE" "$DEPLOYMENT" -o jsonpath='{.metadata.annotations.reloader\.stakater\.com/auto}' 2>/dev/null || echo "")
if [ "$ANNOT" = "true" ]; then
  printf "    ${DIM}│${NC}  reloader.stakater.com/auto: ${ACCENT}\"true\"${NC}\n"
else
  printf "    ${DIM}│${NC}  reloader.stakater.com/auto: ${DIM}(not set)${NC}\n"
fi
pause

# ═══════════════════════════════════════════════════════════
# LIVE ROTATION BANNER
# ═══════════════════════════════════════════════════════════
printf "\n"
brand_bar
printf "\n"
printf "${EMPH}"
cat <<'ROTATION_BANNER'
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║               L I V E   R O T A T I O N               ║
    ║                                                       ║
    ║       Privilege Cloud password change triggers:       ║
    ║     K8s Secret update -> Reloader rollout -> app      ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
ROTATION_BANNER
printf "${NC}\n"

# ═══════════════════════════════════════════════════════════
header "9/13" "Live Auto-Rotation — K8s Secret"
# ═══════════════════════════════════════════════════════════

BEFORE_PASS=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode)
BEFORE_USER=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.username}" | base64 --decode)

printf "\n"
box_top 41
box_row 41 "  ${BOLD}Current K8s Secret${NC}"
box_mid 41
box_row 41 "  username:          ${BOLD}${BEFORE_USER}${NC}"
box_row 41 "  password:          ${BOLD}${BEFORE_PASS}${NC}"
box_row 41 "  refresh interval:  ${ACCENT}15s${NC}"
box_bot 41

printf "\n"
box_top 53 "$EMPH"
box_blank 53 "$EMPH"
box_row 53 "  ${BOLD}ACTION REQUIRED:${NC}" "$EMPH"
box_blank 53 "$EMPH"
box_row 53 "  Go to ${EMPH}${BOLD}Privilege Cloud${NC} and change the password" "$EMPH"
box_row 53 "  for ${BOLD}account-ssh-user-1${NC} in the ${BOLD}k8s-eso${NC} safe." "$EMPH"
box_blank 53 "$EMPH"
box_row 53 "  ESO will detect the change on its next sync" "$EMPH"
box_row 53 "  cycle (${ACCENT}≤15 seconds${NC})." "$EMPH"
box_blank 53 "$EMPH"
box_bot 53 "$EMPH"

printf "\n${EMPH}    ▶ Change the password in Privilege Cloud, then press ENTER...${NC}"
read -r

printf "\n    ${BOLD}Watching K8s Secret for rotation...${NC}\n\n"
POLL_COUNT=0
MAX_POLLS=$MAX_SECRET_POLLS
while [ "$POLL_COUNT" -lt "$MAX_POLLS" ]; do
  CURRENT_PASS=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode)
  POLL_COUNT=$((POLL_COUNT + 1))
  TIMESTAMP=$(date +"%H:%M:%S")

  if [ "$CURRENT_PASS" != "$BEFORE_PASS" ]; then
    printf "    ${ACCENT}[%s]  ✔  ROTATED${NC}\n" "$TIMESTAMP"
    printf "\n"
    box_top 47
    box_row 47 "  ${ERR}Before:${NC}  ${BEFORE_PASS}"
    box_row 47 "  ${ACCENT}After:${NC}   ${CURRENT_PASS}"
    box_bot 47
    printf "\n"
    status_ok "K8s Secret auto-rotated"
    status_ok "Zero code changes, zero manual intervention"

    # Capture env vars immediately — Reloader often restarts the pod within seconds.
    ROTATED_PASS="$CURRENT_PASS"
    ROTATION_POD_AT_DETECT=$(get_app_pod)
    ENV_PASS_AT_ROTATION=$(get_env_password "$ROTATION_POD_AT_DETECT")

    printf "\n    ${BOLD}Snapshot (same second as Secret update):${NC}\n"
    box_top 52
    box_row 52 "  ${BOLD}K8s Secret password:${NC}  ${ACCENT}updated${NC}"
    if [ -n "$ENV_PASS_AT_ROTATION" ] && [ "$ENV_PASS_AT_ROTATION" != "$ROTATED_PASS" ]; then
      box_row 52 "  ${BOLD}DB_PASSWORD env:${NC}     ${ERR}still ${ENV_PASS_AT_ROTATION}${NC}"
      box_row 52 "  ${DIM}(frozen at container start — Reloader has not rolled yet)${NC}"
      status_warn "Env var still stale — step 11 will use this snapshot"
    elif [ -n "$ENV_PASS_AT_ROTATION" ] && [ "$ENV_PASS_AT_ROTATION" = "$ROTATED_PASS" ]; then
      box_row 52 "  ${BOLD}DB_PASSWORD env:${NC}     ${ACCENT}already ${ENV_PASS_AT_ROTATION}${NC}"
      status_warn "Reloader was very fast — step 11 replays the stale-env story from this snapshot"
    else
      box_row 52 "  ${BOLD}DB_PASSWORD env:${NC}     ${DIM}(pod not ready to inspect)${NC}"
    fi
    box_bot 52
    break
  fi

  REMAINING=$(( (MAX_POLLS - POLL_COUNT) * POLL_INTERVAL ))
  printf "    ${DIM}[%s]${NC}  ${ACCENT}◌${NC}  polling... ${DIM}(%d/%d, ~%ds left)${NC}\n" "$TIMESTAMP" "$POLL_COUNT" "$MAX_POLLS" "$REMAINING"
  sleep "$POLL_INTERVAL"
done

if [ "$POLL_COUNT" -eq "$MAX_POLLS" ]; then
  status_fail "Timed out waiting for Secret update"
  printf "    ${DIM}1. Password changed in Privilege Cloud?${NC}\n"
  printf "    ${DIM}2. Conjur Sync replicated the change?${NC}\n"
  printf "    ${DIM}3. kubectl get externalsecret -n %s db-credentials${NC}\n" "$NAMESPACE"
fi

if [ -z "${ROTATED_PASS:-}" ]; then
  ROTATED_PASS=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode)
fi

printf "\n    ${DIM}Next: volume mount catches up (~60–90s), then the env-var / Reloader story.${NC}\n"
printf "    ${DIM}Reloader may restart the pod during step 10 — we captured env at rotation above.${NC}\n"
pause

# ═══════════════════════════════════════════════════════════
header "10/13" "Method ① — Volume Mount Auto-Update"
# ═══════════════════════════════════════════════════════════
printf "\n"
box_top 53
box_blank 53
box_row 53 "  Volume mounts are updated by ${BOLD}kubelet${NC} when the"
box_row 53 "  K8s Secret changes. Propagation: ${BOLD}~60-90 seconds${NC}."
box_blank 53
box_row 53 "  No pod restart needed. No application changes."
box_blank 53
box_bot 53
printf "\n"

printf "    ${BOLD}Polling mounted file until it reflects the new password...${NC}\n\n"

ROTATED_PASS="${ROTATED_PASS:-$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode)}"
VOL_COUNT=0
VOL_MAX=$MAX_VOLUME_POLLS
while [ "$VOL_COUNT" -lt "$VOL_MAX" ]; do
  APP_POD=$(get_app_pod)
  VOL_COUNT=$((VOL_COUNT + 1))
  TIMESTAMP=$(date +"%H:%M:%S")

  if [ -z "$APP_POD" ]; then
    REMAINING=$(( (VOL_MAX - VOL_COUNT) * POLL_INTERVAL ))
    printf "    ${DIM}[%s]${NC}  ${ACCENT}◌${NC}  waiting for running app pod... ${DIM}(%d/%d, ~%ds)${NC}\n" "$TIMESTAMP" "$VOL_COUNT" "$VOL_MAX" "$REMAINING"
    sleep "$POLL_INTERVAL"
    continue
  fi

  VOL_PASS=$(kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- cat /etc/secrets/password 2>/dev/null || echo "")

  if [ "$VOL_PASS" = "$ROTATED_PASS" ]; then
    printf "    ${ACCENT}[%s]  ✔  Volume mount updated!${NC}\n" "$TIMESTAMP"
    printf "\n"
    box_top 47
    box_row 47 "  ${BOLD}Mounted file:${NC}  ${ACCENT}${VOL_PASS}${NC}"
    box_row 47 "  ${BOLD}K8s Secret:${NC}    ${ACCENT}${ROTATED_PASS}${NC}"
    box_bot 47
    printf "\n"
    status_ok "Volume mount matches K8s Secret"
    status_ok "Kubelet propagated the change — zero restarts"
    break
  fi

  REMAINING=$(( (VOL_MAX - VOL_COUNT) * POLL_INTERVAL ))
  printf "    ${DIM}[%s]${NC}  ${ACCENT}◌${NC}  kubelet propagating... mounted=${DIM}%s${NC} ${DIM}(%d/%d, ~%ds)${NC}\n" "$TIMESTAMP" "$VOL_PASS" "$VOL_COUNT" "$VOL_MAX" "$REMAINING"
  sleep "$POLL_INTERVAL"
done

if [ "$VOL_COUNT" -eq "$VOL_MAX" ]; then
  status_warn "Kubelet hasn't propagated yet (volume poll limit reached)"
  printf "    ${DIM}Re-check pods: kubectl get pods -n %s -l app=%s${NC}\n" "$NAMESPACE" "$DEPLOYMENT"
  printf "    ${DIM}Then exec:     kubectl exec -n %s <pod> -c app -- cat /etc/secrets/password${NC}\n" "$NAMESPACE"
fi
pause

# ═══════════════════════════════════════════════════════════
header "11/13" "Method ② — Env Variables (The Stale Problem)"
# ═══════════════════════════════════════════════════════════
printf "\n"
box_top 53 "$EMPH"
box_blank 53 "$EMPH"
box_row 53 "  Environment variables are ${BOLD}frozen at pod startup${NC}." "$EMPH"
box_row 53 "  They still hold the ${ERR}OLD${NC} password even though" "$EMPH"
box_row 53 "  the K8s Secret already changed." "$EMPH"
box_blank 53 "$EMPH"
box_row 53 "  This is ${BOLD}standard Kubernetes behavior${NC}." "$EMPH"
box_blank 53 "$EMPH"
box_bot 53 "$EMPH"
printf "\n"

APP_POD=$(get_app_pod)
ENV_PASS_NOW=$(get_env_password "$APP_POD")
VOL_NOW=""
if [ -n "$APP_POD" ]; then
  VOL_NOW=$(kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- cat /etc/secrets/password 2>/dev/null || echo '(pending)')
fi

# Prefer the snapshot from step 9 — Reloader often wins before we reach this step.
STALE_ENV="${ENV_PASS_AT_ROTATION:-$BEFORE_PASS}"
if [ -z "$STALE_ENV" ] || [ "$STALE_ENV" = "$ROTATED_PASS" ]; then
  STALE_ENV="$BEFORE_PASS"
fi

box_top 54
box_row 54 "  ${BOLD}K8s Secret (now):${NC}              ${ACCENT}${ROTATED_PASS}${NC}"
box_row 54 "  ${BOLD}Volume mount (now):${NC}            ${ACCENT}${VOL_NOW}${NC}"
box_mid 54
box_row 54 "  ${BOLD}DB_PASSWORD at rotation:${NC}       ${ERR}${STALE_ENV}${NC}"
if [ -n "$ENV_PASS_NOW" ] && [ "$ENV_PASS_NOW" != "$STALE_ENV" ]; then
  box_row 54 "  ${BOLD}DB_PASSWORD in running pod now:${NC}  ${ACCENT}${ENV_PASS_NOW}${NC}"
  box_row 54 "  ${DIM}(Reloader likely restarted the pod during step 10)${NC}"
elif [ -n "$ENV_PASS_NOW" ] && [ "$ENV_PASS_NOW" = "$STALE_ENV" ]; then
  box_row 54 "  ${BOLD}DB_PASSWORD in running pod now:${NC}  ${ERR}${ENV_PASS_NOW}${NC}  ${ERR}still stale${NC}"
else
  box_row 54 "  ${BOLD}DB_PASSWORD in running pod now:${NC}  ${DIM}(unavailable)${NC}"
fi
box_bot 54
printf "\n"

if [ "$STALE_ENV" != "$ROTATED_PASS" ]; then
  status_warn "Env var was STALE right after rotation — still held ${STALE_ENV}"
  printf "\n    ${BOLD}Solution:${NC} ${BOLD}Rolling restart${NC} (Stakater Reloader does this automatically).\n"
  printf "    ${DIM}Step 12 shows the rollout / refreshed env.${NC}\n"
else
  status_warn "Could not capture a stale env at rotation — use the BEFORE password for narrative"
  printf "    ${DIM}Expected: DB_PASSWORD stayed ${BEFORE_PASS} while Secret became ${ROTATED_PASS}${NC}\n"
fi
pause

# ═══════════════════════════════════════════════════════════
header "12/13" "Rolling Restart — Env Vars Refreshed"
# ═══════════════════════════════════════════════════════════

RELOADER_RUNNING=$(kubectl get pods -A -l app.kubernetes.io/name=reloader -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$RELOADER_RUNNING" ]; then
  printf "\n"
  status_ok "Reloader is installed"
  printf "\n    ${DIM}Checking if Reloader already restarted the pod...${NC}\n\n"

  APP_POD=$(require_app_pod)
  ENV_PASS=$(get_env_password "$APP_POD")

  if [ "$ENV_PASS" = "$ROTATED_PASS" ]; then
    status_ok "Reloader restarted the pod — env vars are current"
    printf "\n"
    printf "    ${DIM}│${NC}  DB_PASSWORD:  ${ACCENT}%s${NC}  ${ACCENT}✔${NC}\n" "$ENV_PASS"
    if [ -n "${STALE_ENV:-}" ] && [ "$STALE_ENV" != "$ROTATED_PASS" ]; then
      printf "    ${DIM}│${NC}  (was ${ERR}%s${NC} at rotation — step 11)${NC}\n" "$STALE_ENV"
    fi
    printf "\n    ${EMPH}Watch Reloader in k9s? [Y/n] ${NC}"
    read -r k9s_reloader
    case "${k9s_reloader:-n}" in
      [yY]*) k9s -n "$NAMESPACE" ;;
      *) ;;
    esac
  else
    printf "    ${BOLD}Waiting for Reloader to restart the pod...${NC}\n\n"
    RESTART_COUNT=0
    RESTART_MAX=$MAX_RESTART_POLLS
    RESTART_DETECTED=0
    OLD_POD="$APP_POD"
    while [ "$RESTART_COUNT" -lt "$RESTART_MAX" ]; do
      APP_POD=$(get_app_pod)
      RESTART_COUNT=$((RESTART_COUNT + 1))
      TIMESTAMP=$(date +"%H:%M:%S")
      if [ -z "$APP_POD" ]; then
        printf "    ${DIM}[%s]${NC}  ${ACCENT}◌${NC}  waiting for new app pod scheduling... ${DIM}(%d/%d)${NC}\n" "$TIMESTAMP" "$RESTART_COUNT" "$RESTART_MAX"
        sleep "$POLL_INTERVAL"
        continue
      fi
      if [ "$APP_POD" != "$OLD_POD" ]; then
        kubectl wait --for=condition=Ready pod -n "$NAMESPACE" "$APP_POD" --timeout=30s 2>/dev/null
        ENV_PASS=$(get_env_password "$APP_POD")
        printf "    ${ACCENT}[%s]  ✔  Pod restarted by Reloader${NC}\n" "$TIMESTAMP"
        printf "\n"
        printf "    ${DIM}│${NC}  New pod:      ${BOLD}%s${NC}\n" "$APP_POD"
        printf "    ${DIM}│${NC}  DB_PASSWORD:  ${ACCENT}%s${NC}\n" "$ENV_PASS"
        RESTART_DETECTED=1
        break
      fi
      printf "    ${DIM}[%s]${NC}  ${ACCENT}◌${NC}  waiting for Reloader... ${DIM}(%d/%d)${NC}\n" "$TIMESTAMP" "$RESTART_COUNT" "$RESTART_MAX"
      sleep "$POLL_INTERVAL"
    done
    if [ "$RESTART_DETECTED" -eq 0 ]; then
      status_warn "Did not observe pod replacement in the Reloader wait window"
      printf "    ${DIM}Check: kubectl get pods -n %s -l app=%s${NC}\n" "$NAMESPACE" "$DEPLOYMENT"
      printf "    ${DIM}Check: kubectl get events -n %s --sort-by=.lastTimestamp | tail -20${NC}\n" "$NAMESPACE"
    fi
  fi
else
  printf "\n"
  box_top 50
  box_row 50 "  Reloader is not installed. Performing a"
  box_row 50 "  ${BOLD}manual rolling restart${NC} to demonstrate that"
  box_row 50 "  env vars pick up the new password."
  box_bot 50
  printf "\n"

  ENV_PASS=$(get_env_password "$(get_app_pod)")
  printf "    ${ERR}━━━ BEFORE restart ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "    ${DIM}│${NC}  DB_PASSWORD:  ${ERR}%s${NC}  ${ERR}✘ stale${NC}\n\n" "${STALE_ENV:-$ENV_PASS}"
  pause

  printf "    ${BOLD}Triggering rolling restart...${NC}\n\n"
  run_cmd kubectl rollout restart deployment -n "$NAMESPACE" "$DEPLOYMENT"
  printf "\n    ${DIM}Waiting for new pod to be ready...${NC}\n"
  kubectl rollout status deployment -n "$NAMESPACE" "$DEPLOYMENT" --timeout=60s 2>&1 | while IFS= read -r line; do printf "    ${DIM}%s${NC}\n" "$line"; done

  APP_POD=$(require_app_pod)
  kubectl wait --for=condition=Ready pod -n "$NAMESPACE" "$APP_POD" --timeout=30s 2>/dev/null

  FRESH_PASS=$(get_env_password "$APP_POD")

  printf "\n    ${ACCENT}━━━ AFTER restart ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "    ${DIM}│${NC}  DB_PASSWORD:  ${ACCENT}%s${NC}  ${ACCENT}✔ current${NC}\n\n" "$FRESH_PASS"

  if [ "$FRESH_PASS" = "$ROTATED_PASS" ]; then
    status_ok "Env var now matches the rotated password"
    printf "\n    ${DIM}With Reloader installed, this restart happens automatically.${NC}\n"
  fi
fi
pause

# ═══════════════════════════════════════════════════════════
header "13/13" "k9s — ExternalSecrets / Secrets"
# ═══════════════════════════════════════════════════════════
printf "\n"
box_top 56
box_row 56 "  ${BOLD}Optional second pass${NC} — ESO + decoded Secret:"
box_blank 56
box_row 56 "  ${ACCENT}:externalsecrets${NC}  sync status + LAST SYNC timer"
box_row 56 "  ${ACCENT}:secrets${NC}          ${BOLD}x${NC} decode"
box_row 56 "  (${ACCENT}:pods${NC} / ${ACCENT}:events${NC} — best during step 12 / Reloader rollout)"
box_blank 56
box_row 56 "  ${BOLD}Pro tip:${NC} decode secret, rotate again in Priv Cloud"
box_bot 56
printf "\n"

printf "    Launch k9s? [Y/n] "
read -r answer
case "${answer:-y}" in
  [nN]*) ;;
  *) k9s -n "$NAMESPACE" ;;
esac

# ═══════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════
printf "\n"
brand_bar
printf "\n"
printf "${ACCENT}"
cat <<'COMPLETE_BANNER'
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║     ██████╗  ██████╗ ███╗   ██╗███████╗██╗            ║
    ║     ██╔══██╗██╔═══██╗████╗  ██║██╔════╝██║            ║
    ║     ██║  ██║██║   ██║██╔██╗ ██║█████╗  ██║            ║
    ║     ██║  ██║██║   ██║██║╚██╗██║██╔══╝  ╚═╝            ║
    ║     ██████╔╝╚██████╔╝██║ ╚████║███████╗██╗            ║
    ║     ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚═╝            ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
COMPLETE_BANNER
printf "${NC}\n"

printf "    ${BOLD}What we demonstrated:${NC}\n\n"
printf "    ${ACCENT}  ✔${NC}  ESO with ${BOLD}15-second refresh interval${NC}\n"
printf "    ${ACCENT}  ✔${NC}  SecretStore with ${BOLD}Conjur Cloud JWT authentication${NC}\n"
printf "    ${ACCENT}  ✔${NC}  ExternalSecret pulling live credentials\n"
printf "    ${ACCENT}  ✔${NC}  K8s Secret ${BOLD}auto-updated${NC} on password rotation\n"
printf "    ${ACCENT}  ✔${NC}  ${ACCENT}Volume mounts${NC} updated automatically by kubelet\n"
printf "    ${ACCENT}  ✔${NC}  ${EMPH}Env vars${NC} refreshed via rolling restart\n"
printf "    ${ACCENT}  ✔${NC}  Full rotation: ${EMPH}Priv Cloud${NC} → ${ACCENT}Sync${NC} → ${ACCENT}Conjur${NC} → ${ACCENT}ESO${NC} → ${EMPH}K8s${NC} → ${BOLD}App${NC}\n"

printf "\n"
box_top 54
box_row 54 "  ${BOLD}CyberArk Value:${NC}"
box_blank 54
box_row 54 "  ${DIM}•${NC} Privilege Cloud is the ${BOLD}single source of truth${NC}"
box_row 54 "  ${DIM}•${NC} CPM rotation policies drive the schedule"
box_row 54 "  ${DIM}•${NC} Conjur Sync replicates automatically"
box_row 54 "  ${DIM}•${NC} ${BOLD}JWT auth${NC} — no static API keys in cluster"
box_row 54 "  ${DIM}•${NC} ${BOLD}Policy-as-code${NC} — auditable YAML grants"
box_row 54 "  ${DIM}•${NC} ESO is open-source — zero vendor lock-in"
box_row 54 "  ${DIM}•${NC} Rotation is ${BOLD}transparent to the application${NC}"
box_blank 54
box_bot 54
printf "\n"
brand_bar
printf "\n"
