#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

if [[ -f /etc/profile.d/cyberark.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

if [[ -f "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" ]]; then
  # shellcheck disable=SC1091
  source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
fi

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[FAIL] required tool not found: $1" >&2
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "[FAIL] required file not found: $1" >&2
    exit 1
  fi
}

step() {
  printf "\n[%s] %s\n" "$1" "$2"
}

pass() {
  printf "[PASS] %s\n" "$1"
}

require_tool kubectl
require_tool jq

: "${LAB_ID:?LAB_ID is not set. Source tenant vars or export LAB_ID before validating.}"

require_file "$SCRIPT_DIR/setup/vars.env"
require_file "$SCRIPT_DIR/setup/swa/swa_registered.env"

set -a
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup/vars.env"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup/swa/swa_registered.env"
if [[ -f "$SCRIPT_DIR/setup/k8s/giftapp_images.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/setup/k8s/giftapp_images.env"
fi
set +a

NS_HARDCODED="${NAMESPACE_HARDCODED:?NAMESPACE_HARDCODED is not set}"
NS_SWA="${NAMESPACE_SWA:?NAMESPACE_SWA is not set}"
SWA_NS="${SWA_NAMESPACE:-swa-system}"
FORCE_FRESH_SWA_AUTH="${FORCE_FRESH_SWA_AUTH:-true}"
EXPECTED_SPIFFE_SUB="${SWA_SPIFFE_PREFIX:?SWA_SPIFFE_PREFIX is not set}/workload/1000"

step "1/8" "Check Kubernetes connectivity"
kubectl version --client >/dev/null
kubectl get nodes >/dev/null
pass "kubectl can reach the cluster"

step "2/8" "Wait for demo pods to be ready"
kubectl wait --for=condition=Ready pod --all -n "$SWA_NS" --timeout=120s
kubectl wait --for=condition=Ready pod --all -n "$NS_HARDCODED" --timeout=120s
kubectl wait --for=condition=Ready pod --all -n "$NS_SWA" --timeout=120s
pass "all pods are Ready"

step "3/8" "Check SWA server and agent"
kubectl rollout status deployment/swa-server -n "$SWA_NS" --timeout=120s >/dev/null
kubectl rollout status daemonset/swa-agent -n "$SWA_NS" --timeout=120s >/dev/null
pass "swa-server deployment and swa-agent daemonset are available"

step "4/8" "Validate attack app exposes Kubernetes-mounted secrets"
kubectl exec -n "$NS_HARDCODED" deploy/giftapp-hardcoded -- \
  sh -c 'test -s /etc/secrets/GIFTAPP_API_KEY && test -s /etc/secrets/DB_PASS'

sa_token=$(kubectl exec -n "$NS_HARDCODED" deploy/giftapp-hardcoded -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token)
kubectl get secret giftapp-hardcoded-secrets -n "$NS_HARDCODED" \
  --token="$sa_token" -o json >/dev/null
pass "giftapp-hardcoded can read its mounted secret files and Kubernetes Secret"

step "5/8" "Validate defended app has no sensitive secret files"
swa_secret_keys=$(kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- ls /etc/secrets/)
if printf '%s\n' "$swa_secret_keys" | grep -Eq '^(DB_PASS|GIFTAPP_API_KEY)$'; then
  echo "[FAIL] giftapp-swa has sensitive files mounted in /etc/secrets" >&2
  printf '%s\n' "$swa_secret_keys" >&2
  exit 1
fi

kubectl get secret giftapp-swa-secrets -n "$NS_SWA" -o json \
  | jq -e '(.data | has("DB_PASS") | not) and (.data | has("GIFTAPP_API_KEY") | not)' >/dev/null
pass "giftapp-swa only has non-sensitive Kubernetes Secret entries"

step "6/8" "Validate SWA socket is mounted"
kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
  test -S "${SWA_SOCKET_PATH:-/tmp/swa-agent/public/api.sock}"
pass "SWA workload API socket is present"

step "7/8" "Force fresh SWA authentication"
if [[ "$FORCE_FRESH_SWA_AUTH" == "true" ]]; then
  kubectl rollout restart deployment/giftapp-swa -n "$NS_SWA" >/dev/null
  kubectl rollout status deployment/giftapp-swa -n "$NS_SWA" --timeout=180s >/dev/null
  kubectl wait --for=condition=Available deployment/giftapp-swa -n "$NS_SWA" --timeout=180s >/dev/null
  pass "giftapp-swa restarted to force a fresh JWT-SVID and Conjur authentication"
else
  pass "skipped restart because FORCE_FRESH_SWA_AUTH=$FORCE_FRESH_SWA_AUTH"
fi

step "8/8" "Validate defended app fetched secrets through SWA and Conjur"
swa_pod=$(kubectl get pods -n "$NS_SWA" -l app=giftapp-swa \
  --field-selector=status.phase=Running -o json \
  | jq -r '.items | sort_by(.metadata.creationTimestamp) | last.metadata.name')
if [[ -z "$swa_pod" || "$swa_pod" == "null" ]]; then
  echo "[FAIL] no Running giftapp-swa pod found" >&2
  exit 1
fi

health_json=$(kubectl exec -n "$NS_SWA" "pod/$swa_pod" -- \
  wget -qO- --no-check-certificate https://127.0.0.1:8443/healthz)

printf '%s\n' "$health_json" | jq -e '
  .mode == "swa" and
  .swaReady == true and
  .secrets.dbPassword == "present" and
  .secrets.giftappApiKey == "present"
' >/dev/null

swa_logs=$(kubectl logs -n "$NS_SWA" "pod/$swa_pod" --tail=80)
printf '%s\n' "$swa_logs" | grep -F "sub=\"$EXPECTED_SPIFFE_SUB\"" >/dev/null
printf '%s\n' "$swa_logs" | grep -F "loaded secrets through SWA JWT-SVID and Conjur" >/dev/null
pass "giftapp-swa health is ready and fresh logs show expected SPIFFE subject: $EXPECTED_SPIFFE_SUB"

printf "\nValidation completed successfully.\n"
