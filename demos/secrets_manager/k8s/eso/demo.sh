#!/bin/bash
# ESO + CyberArk Conjur Cloud Demo Script (~10 minutes)
# Interactive walkthrough: press ENTER to advance between steps.
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

NAMESPACE="external-secrets"
ESO_DIR="$(cd "$(dirname "$0")" && pwd)"

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
    printf "${RED}ERROR: cannot reach the Kubernetes API at:${NC}\n" >&2
    kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' >&2 2>/dev/null || true
    printf "\n${YELLOW}Start the cluster first:${NC}\n" >&2
    printf "  minikube start --driver=docker         ${YELLOW}# or your cluster of choice${NC}\n" >&2
    printf "  kubectl cluster-info                   ${YELLOW}# should report Running${NC}\n" >&2
    exit 1
  fi
  if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    printf "${RED}ERROR: namespace '%s' is missing.${NC}\n" "$NAMESPACE" >&2
    printf "${YELLOW}Run the demo setup first:${NC}\n" >&2
    printf "  cd %s/.. && bash setup.sh\n" "$ESO_DIR" >&2
    exit 1
  fi
  if ! kubectl get deploy -n "$NAMESPACE" -l 'app.kubernetes.io/name=external-secrets' -o name >/dev/null 2>&1 \
     || [[ -z "$(kubectl get pods -n "$NAMESPACE" -l 'app.kubernetes.io/name=external-secrets' -o name 2>/dev/null)" ]]; then
    printf "${YELLOW}WARN: ESO controller not detected in namespace %s. Continuing anyway.${NC}\n" "$NAMESPACE"
  fi
}

# ─────────────────────────────────────────────────────────
preflight

header "ESO + CyberArk Secrets Manager Demo"
cat <<'INTRO'

  This demo shows External Secrets Operator (ESO) pulling
  credentials from CyberArk Conjur Cloud into Kubernetes
  secrets — zero application code changes required.

  Flow:
    Privilege Cloud Safe → Conjur Sync → Conjur Cloud
      → ESO (JWT auth) → K8s Secret

INTRO
pause

# ─────────────────────────────────────────────────────────
header "Step 1: ESO Infrastructure"
printf "ESO runs as a controller in the ${BOLD}external-secrets${NC} namespace.\n"
printf "It watches for SecretStore and ExternalSecret resources.\n\n"
run_cmd kubectl get pods -n "$NAMESPACE"
pause

# ─────────────────────────────────────────────────────────
header "Step 2: SecretStore — Conjur JWT Authentication"
cat <<'TALK'

  The SecretStore configures HOW to reach Conjur Cloud:
    • URL:          Conjur Cloud API endpoint
    • serviceID:    JWT authenticator (authn-jwt/zg-eso)
    • account:      Conjur account name
    • JWT source:   K8s service account token

  When ESO needs a secret, it mints a JWT from the service
  account and authenticates to Conjur via authn-jwt.

TALK
printf "${BOLD}SecretStore manifest:${NC}\n"
run_cmd cat "$ESO_DIR/secretstore.yaml"
pause

printf "${BOLD}SecretStore status:${NC}\n"
run_cmd kubectl get secretstore -n "$NAMESPACE" conjur -o wide
pause

# ─────────────────────────────────────────────────────────
header "Step 3: Service Account Identity"
cat <<'TALK'

  ESO uses a dedicated K8s service account to get a JWT.
  The JWT 'sub' claim becomes the workload identity in Conjur:

    system:serviceaccount:external-secrets:zg-eso-service-account

  Conjur maps this to a host via identity-path + sub claim,
  then checks safe membership before returning the secret.

TALK
run_cmd kubectl get sa -n "$NAMESPACE" zg-eso-service-account
pause

# ─────────────────────────────────────────────────────────
header "Step 4: Conjur Policy — Identity & Access"
cat <<'TALK'

  Three policies wire up the authorization in Conjur Cloud:

  1. Workload host     — defines the identity + JWT annotation
  2. Safe access grant — adds host to k8s-eso/delegation/consumers
  3. Authenticator     — allows host to use authn-jwt/zg-eso

TALK
for f in "$ESO_DIR"/conjur-policy/*.yaml; do
  printf "${BOLD}── $(basename "$f") ──${NC}\n"
  cat "$f"
  echo
done
pause

# ─────────────────────────────────────────────────────────
header "Step 5: ExternalSecret — What To Fetch"
cat <<'TALK'

  The ExternalSecret defines WHAT secrets to pull:
    • secretStoreRef:  points to the 'conjur' SecretStore
    • remoteRef.key:   Conjur variable path
    • target:          K8s Secret name to create

  Conjur variable paths mirror Privilege Cloud structure:
    data/vault/<safe>/<account>/<property>

TALK
run_cmd cat "$ESO_DIR/externalsecret.yaml"
pause

printf "${BOLD}ExternalSecret sync status:${NC}\n"
run_cmd kubectl get externalsecret -n "$NAMESPACE" conjur -o wide
pause

# ─────────────────────────────────────────────────────────
header "Step 6: The Payoff — K8s Secret"
cat <<'TALK'

  ESO created a native K8s Secret from the Conjur variables.
  Any pod in this namespace can mount it — no SDK, no sidecar,
  no application changes needed.

TALK
run_cmd kubectl get secret -n "$NAMESPACE" conjur-secrets

printf "\n${BOLD}Decoded values:${NC}\n"
printf "  username: "
kubectl get secret -n "$NAMESPACE" conjur-secrets -o jsonpath="{.data.username}" | base64 --decode
printf "\n  password: "
kubectl get secret -n "$NAMESPACE" conjur-secrets -o jsonpath="{.data.password}" | base64 --decode
echo
pause

# ─────────────────────────────────────────────────────────
header "Step 7: Live Rotation Demo"

BEFORE_PASS=$(kubectl get secret -n "$NAMESPACE" conjur-secrets -o jsonpath="{.data.password}" | base64 --decode)
printf "${BOLD}Current password in K8s:${NC} %s\n" "$BEFORE_PASS"
printf "${BOLD}Refresh interval:${NC}       "
kubectl get externalsecret -n "$NAMESPACE" conjur -o jsonpath="{.spec.refreshInterval}"
echo
# Rotation poll cadence — env-configurable so presenters can ride out Conjur Sync lag.
ROT_INTERVAL="${CYBR_DEMO_POLL_INTERVAL:-10}"
ROT_WINDOW_SECONDS="${CYBR_DEMO_ROTATION_TIMEOUT:-360}"
ROT_MAX_POLLS=$(( ROT_WINDOW_SECONDS / ROT_INTERVAL ))
[ "$ROT_MAX_POLLS" -lt 1 ] && ROT_MAX_POLLS=1

cat <<TALK

  Now go to Privilege Cloud and change the password for
  account-ssh-user-1 in the k8s-eso safe.

  End-to-end propagation: CPM (in Priv Cloud) -> Conjur Sync ->
  Conjur Cloud -> ESO refresh (15s) -> K8s Secret. Conjur Sync
  is the slowest leg and can lag several minutes in busy tenants.

  This script polls every ${ROT_INTERVAL}s for up to ${ROT_WINDOW_SECONDS}s
  (override: CYBR_DEMO_POLL_INTERVAL, CYBR_DEMO_ROTATION_TIMEOUT).

TALK
printf "${YELLOW}▶ Change the password in Privilege Cloud, then press ENTER to start watching...${NC}"
read -r

watch_rotation() {
  local before="$1" interval="$2" max="$3" count=0 current ts last_sync
  printf "\n${BOLD}Watching for rotation (interval=%ss, window=%ss)...${NC}\n" "$interval" "$((interval * max))"
  while [ "$count" -lt "$max" ]; do
    current=$(kubectl get secret -n "$NAMESPACE" conjur-secrets -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode 2>/dev/null || echo "")
    count=$((count + 1))
    ts=$(date +"%H:%M:%S")
    if [ -n "$current" ] && [ "$current" != "$before" ]; then
      printf "  ${GREEN}[%s] ✓ ROTATED${NC}\n" "$ts"
      printf "\n${BOLD}Before:${NC} %s\n" "$before"
      printf "${BOLD}After:${NC}  %s\n" "$current"
      printf "\n${GREEN}Password updated in K8s — zero pod restarts, zero redeployments.${NC}\n"
      return 0
    fi
    last_sync=$(kubectl get externalsecret -n "$NAMESPACE" conjur -o jsonpath='{.status.refreshTime}' 2>/dev/null || echo "")
    printf "  [%s] polling... unchanged (%d/%d, last ESO sync: %s)\n" "$ts" "$count" "$max" "${last_sync:-?}"
    sleep "$interval"
  done
  return 1
}

while ! watch_rotation "$BEFORE_PASS" "$ROT_INTERVAL" "$ROT_MAX_POLLS"; do
  printf "\n${YELLOW}No change after %ss. Conjur Sync may still be catching up.${NC}\n" \
    "$((ROT_INTERVAL * ROT_MAX_POLLS))"
  printf "${BOLD}Diagnostics:${NC}\n"
  printf "  ExternalSecret status:\n"
  kubectl get externalsecret -n "$NAMESPACE" conjur 2>&1 | sed 's/^/    /'
  printf "  Last reconciler errors (if any):\n"
  kubectl logs -n "$NAMESPACE" deploy/external-secrets --tail=3 2>&1 | grep -E "error|Reconciler" | sed 's/^/    /' | head -3 || true
  printf "\n${YELLOW}Keep watching another %ss? [Y/n]: ${NC}" "$((ROT_INTERVAL * ROT_MAX_POLLS))"
  read -r continue_ans
  case "${continue_ans:-y}" in
    [nN]*) printf "${RED}Manual check: kubectl get secret -n %s conjur-secrets -o jsonpath=\"{.data.password}\" | base64 --decode${NC}\n" "$NAMESPACE"; break ;;
    *) BEFORE_PASS=$(kubectl get secret -n "$NAMESPACE" conjur-secrets -o jsonpath="{.data.password}" | base64 --decode) ;;
  esac
done
pause

# ─────────────────────────────────────────────────────────
header "Step 8: Visual Exploration with k9s"
cat <<'TALK'

  k9s gives a live dashboard view of the ESO resources.

  Suggested views once inside k9s:
    :secretstores        — see Conjur connection status
    :externalsecrets     — see sync status + last refresh
    :secrets             — find conjur-secrets, press 'x' to decode
    :pods                — ESO controller health

  Press 'd' on any resource to describe, 'l' for logs.

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
    ✓ ESO installed via Helm with CRDs
    ✓ SecretStore with Conjur Cloud JWT authentication
    ✓ K8s service account as workload identity
    ✓ Conjur policy: host, safe access, authenticator grant
    ✓ ExternalSecret pulling live credentials
    ✓ Native K8s Secret — zero app changes
    ✓ Automatic rotation via refresh interval

  Key CyberArk value:
    • Secrets stay in Privilege Cloud (single source of truth)
    • Conjur Sync replicates to Conjur Cloud automatically
    • JWT auth — no static API keys stored in the cluster
    • Policy-as-code — all access grants are auditable YAML
    • ESO is open-source — no vendor lock-in on the K8s side

SUMMARY
