#!/bin/bash
# Secrets Provider sidecar + CyberArk Conjur Cloud Demo Script (~10 minutes)
# Interactive walkthrough: press ENTER to advance between steps.
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

NAMESPACE="sp-sidecar"
SECRET_NAME="db-credentials"
DEPLOYMENT="sidecar-demo-app"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

pause() {
  printf "\n${YELLOW}▶ Press ENTER to continue...${NC}"
  read -r
  echo
}

header() {
  printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${BOLD}  %s${NC}\n" "$1"
  printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

run_cmd() {
  printf "${GREEN}\$ %s${NC}\n" "$*"
  "$@"
}

preflight() {
  if ! command -v kubectl >/dev/null 2>&1; then
    printf "${RED}ERROR: kubectl not found in PATH.${NC}\n" >&2
    exit 1
  fi
  if ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
    printf "${RED}ERROR: cannot reach the Kubernetes API at:${NC} %s\n" \
      "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)" >&2
    printf "${YELLOW}Start the cluster first:${NC}\n" >&2
    printf "  minikube start --driver=docker\n" >&2
    printf "  kubectl cluster-info\n" >&2
    exit 1
  fi
  if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    printf "${RED}ERROR: namespace '%s' is missing.${NC}\n" "$NAMESPACE" >&2
    printf "${YELLOW}Run the demo setup first:${NC}\n" >&2
    printf "  bash %s/setup.sh\n" "$DEMO_DIR" >&2
    exit 1
  fi
}

get_app_pod() {
  kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────
header "Secrets Provider Sidecar + CyberArk Demo"
cat <<'INTRO'

  This demo shows the CyberArk Secrets Provider for Kubernetes
  running as a SIDECAR — it authenticates with a pod JWT, fetches
  Conjur variables, and writes a native Kubernetes Secret.

  Flow:
    Privilege Cloud Safe → Conjur Sync → Conjur Cloud
      → Secrets Provider sidecar (JWT auth) → K8s Secret

  Compare to ESO: no ExternalSecret CRDs — the provider runs
  beside your app container in the same pod.

INTRO
pause

# ─────────────────────────────────────────────────────────
header "Step 1: Pod Architecture — App + Sidecar"
cat <<'TALK'

  One pod, two containers:
    • app          — your workload (reads K8s Secret via env)
    • cyberark-secrets-provider-for-k8s — sidecar

  The sidecar shares the pod service account JWT and refreshes
  the K8s Secret on an interval (15s in this demo).

TALK
run_cmd kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT"
pause

# ─────────────────────────────────────────────────────────
header "Step 2: Conjur Connection — conjur-connect ConfigMap"
cat <<'TALK'

  The sidecar reads CyberArk connection settings from a ConfigMap:
    • CONJUR_APPLIANCE_URL  — Conjur Cloud API
    • CONJUR_AUTHN_URL      — authn-jwt endpoint
    • AUTHENTICATOR_ID      — JWT authenticator service ID

TALK
run_cmd kubectl get configmap -n "$NAMESPACE" conjur-connect -o yaml
pause

# ─────────────────────────────────────────────────────────
header "Step 3: Service Account Identity"
cat <<'TALK'

  The pod service account mints a projected JWT (audience: conjur).
  The JWT 'sub' claim is the workload identity in Conjur:

    system:serviceaccount:sp-sidecar:sp-sidecar-sa

TALK
run_cmd kubectl get sa -n "$NAMESPACE" sp-sidecar-sa
pause

# ─────────────────────────────────────────────────────────
header "Step 4: Conjur Policy — Identity & Access"
cat <<'TALK'

  Three policies wire up authorization (same k8s-eso safe as ESO):

  1. Workload host     — defines identity + JWT sub annotation
  2. Safe access grant — adds host to k8s-eso/delegation/consumers
  3. Authenticator     — allows host to use authn-jwt/zg-eso

TALK
for f in "$DEMO_DIR"/conjur-policy/*.yaml; do
  printf "${BOLD}── $(basename "$f") ──${NC}\n"
  cat "$f"
  echo
done
pause

# ─────────────────────────────────────────────────────────
header "Step 5: Secret Mapping — conjur-map"
cat <<'TALK'

  The db-credentials Secret tells the sidecar WHICH Conjur variables
  to fetch and HOW to name them in Kubernetes:

    username → data/vault/k8s-eso/account-ssh-user-1/username
    password → data/vault/k8s-eso/account-ssh-user-1/password

  The sidecar populates the secret keys; the app never talks to Conjur.

TALK
run_cmd cat "$DEMO_DIR/secret.yaml"
pause

# ─────────────────────────────────────────────────────────
header "Step 6: Deployment — Sidecar Annotations & Env"
cat <<'TALK'

  Pod annotations enable refresh without redeploying:
    conjur.org/container-mode: sidecar
    conjur.org/secrets-refresh-enabled: "true"
    conjur.org/secrets-refresh-interval: 15s

  Sidecar env:
    CONTAINER_MODE=sidecar
    K8S_SECRETS=db-credentials
    SECRETS_DESTINATION=k8s_secrets

TALK
run_cmd cat "$DEMO_DIR/deployment.yaml"
pause

# ─────────────────────────────────────────────────────────
header "Step 7: The Payoff — K8s Secret"
cat <<'TALK'

  The sidecar created/updated a native K8s Secret from Conjur.
  Inspect the data keys (not conjur-map — that is the mapping spec).

TALK
run_cmd kubectl get secret -n "$NAMESPACE" "$SECRET_NAME"

printf "\n${BOLD}Decoded values:${NC}\n"
printf "  username: "
kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.username}" | base64 --decode
printf "\n  password: "
kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode
echo
pause

# ─────────────────────────────────────────────────────────
header "Step 8: Application Consumption"
cat <<'TALK'

  The app container reads the secret via secretKeyRef env vars.
  Note: env vars are fixed at container start — after rotation the
  K8s Secret updates first; the app may need a restart to pick up
  new env values (see eso-reloader/ for the Reloader pattern).

TALK
APP_POD=$(get_app_pod)
if [ -n "$APP_POD" ]; then
  run_cmd kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- printenv DB_USERNAME
  run_cmd kubectl exec -n "$NAMESPACE" "$APP_POD" -c app -- printenv DB_PASSWORD
else
  printf "${RED}No running app pod found.${NC}\n"
fi
pause

# ─────────────────────────────────────────────────────────
header "Step 9: Sidecar Logs"
cat <<'TALK'

  The provider sidecar logs authentication and secret sync events.
  Useful when debugging JWT or Conjur policy issues.

TALK
if [ -n "$APP_POD" ]; then
  run_cmd kubectl logs -n "$NAMESPACE" "$APP_POD" -c cyberark-secrets-provider-for-k8s --tail=30
else
  APP_POD=$(get_app_pod)
  [ -n "$APP_POD" ] && run_cmd kubectl logs -n "$NAMESPACE" "$APP_POD" -c cyberark-secrets-provider-for-k8s --tail=30
fi
pause

# ─────────────────────────────────────────────────────────
header "Step 10: Live Rotation Demo"

BEFORE_PASS=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode)
printf "${BOLD}Current password in K8s:${NC} %s\n" "$BEFORE_PASS"
# Rotation poll cadence — env-configurable so presenters can ride out Conjur Sync lag.
ROT_INTERVAL="${CYBR_DEMO_POLL_INTERVAL:-10}"
ROT_WINDOW_SECONDS="${CYBR_DEMO_ROTATION_TIMEOUT:-360}"
ROT_MAX_POLLS=$(( ROT_WINDOW_SECONDS / ROT_INTERVAL ))
[ "$ROT_MAX_POLLS" -lt 1 ] && ROT_MAX_POLLS=1

cat <<TALK

  Go to Privilege Cloud and change the password for
  account-ssh-user-1 in the k8s-eso safe.

  End-to-end propagation: CPM (in Priv Cloud) -> Conjur Sync ->
  Conjur Cloud -> sidecar refresh (15s) -> K8s Secret. Conjur Sync
  is the slowest leg and can lag several minutes in busy tenants.

  This script polls every ${ROT_INTERVAL}s for up to ${ROT_WINDOW_SECONDS}s
  (override: CYBR_DEMO_POLL_INTERVAL, CYBR_DEMO_ROTATION_TIMEOUT).

TALK
printf "${YELLOW}▶ Change the password in Privilege Cloud, then press ENTER to start watching...${NC}"
read -r

watch_rotation_sidecar() {
  local before="$1" interval="$2" max="$3" count=0 current ts
  printf "\n${BOLD}Watching K8s Secret for rotation (interval=%ss, window=%ss)...${NC}\n" "$interval" "$((interval * max))"
  while [ "$count" -lt "$max" ]; do
    current=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode 2>/dev/null || echo "")
    count=$((count + 1))
    ts=$(date +"%H:%M:%S")
    if [ -n "$current" ] && [ "$current" != "$before" ]; then
      printf "  ${GREEN}[%s] ✓ ROTATED${NC}\n" "$ts"
      printf "\n${BOLD}Before:${NC} %s\n" "$before"
      printf "${BOLD}After:${NC}  %s\n" "$current"
      printf "\n${GREEN}K8s Secret updated by the sidecar — no ESO controller required.${NC}\n"
      return 0
    fi
    printf "  [%s] polling... unchanged (%d/%d)\n" "$ts" "$count" "$max"
    sleep "$interval"
  done
  return 1
}

while ! watch_rotation_sidecar "$BEFORE_PASS" "$ROT_INTERVAL" "$ROT_MAX_POLLS"; do
  printf "\n${YELLOW}No change after %ss. Conjur Sync may still be catching up.${NC}\n" \
    "$((ROT_INTERVAL * ROT_MAX_POLLS))"
  printf "${BOLD}Sidecar last 5 log lines:${NC}\n"
  sc_pod=$(get_app_pod)
  if [ -n "$sc_pod" ]; then
    kubectl logs -n "$NAMESPACE" "$sc_pod" -c cyberark-secrets-provider-for-k8s --tail=5 2>&1 | sed 's/^/    /' | head -10
  fi
  printf "\n${YELLOW}Keep watching another %ss? [Y/n]: ${NC}" "$((ROT_INTERVAL * ROT_MAX_POLLS))"
  read -r continue_ans
  case "${continue_ans:-y}" in
    [nN]*) printf "${RED}Manual check: kubectl get secret -n %s %s -o jsonpath=\"{.data.password}\" | base64 --decode${NC}\n" "$NAMESPACE" "$SECRET_NAME"; break ;;
    *) BEFORE_PASS=$(kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" -o jsonpath="{.data.password}" | base64 --decode) ;;
  esac
done
pause

# ─────────────────────────────────────────────────────────
header "Step 11: Visual Exploration with k9s"
cat <<'TALK'

  Suggested views in k9s (namespace sp-sidecar):
    :pods     — two containers per pod; 'l' on sidecar for logs
    :secrets  — db-credentials; press 'x' to decode
    :sa       — sp-sidecar-sa workload identity

TALK
printf "Launch k9s? (y/n) "
read -r answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
  k9s -n "$NAMESPACE"
fi

# ─────────────────────────────────────────────────────────
header "Demo Complete"
cat <<'SUMMARY'

  What we demonstrated:
    ✓ CyberArk Secrets Provider for K8s as a sidecar
    ✓ Pod JWT → authn-jwt/zg-eso → Conjur Cloud
    ✓ conjur-map Secret defines variable → key mapping
    ✓ Native K8s Secret populated beside the app
    ✓ 15s refresh interval — live rotation into K8s

  vs ESO (demos/secrets_manager/k8s/eso/):
    • Sidecar: provider in-pod, no cluster-wide ESO install
    • ESO:     cluster controller + SecretStore / ExternalSecret CRDs

  Key CyberArk value:
    • Privilege Cloud remains the source of truth
    • JWT auth — no static API keys in the cluster
    • Policy-as-code Conjur grants — auditable YAML
    • Works with standard secretKeyRef / volume mounts

SUMMARY
