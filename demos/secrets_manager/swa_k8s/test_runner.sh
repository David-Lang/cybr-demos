#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/artifacts"

if [[ -f /etc/profile.d/cyberark.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

mkdir -p "$ARTIFACTS_DIR"
cd "$SCRIPT_DIR"

log_step() {
  printf "\n[%s] %s\n" "$1" "$2"
}

log_step "1/3" "Run demo setup"
bash ./setup.sh | tee "$ARTIFACTS_DIR/setup.log"

log_step "2/3" "Validate deployed demo"
bash ./validate.sh | tee "$ARTIFACTS_DIR/validate.log"

log_step "3/3" "Capture Kubernetes artifacts"
set -a
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup/vars.env"
set +a

kubectl get pods -A > "$ARTIFACTS_DIR/pods.txt"
kubectl get events -A --sort-by=.lastTimestamp > "$ARTIFACTS_DIR/events.txt" || true
kubectl get all -n "${SWA_NAMESPACE:-swa-system}" > "$ARTIFACTS_DIR/swa-system.txt" || true
kubectl get all -n "$NAMESPACE_HARDCODED" > "$ARTIFACTS_DIR/hardcoded-namespace.txt" || true
kubectl get all -n "$NAMESPACE_SWA" > "$ARTIFACTS_DIR/swa-namespace.txt" || true
kubectl logs -n "${SWA_NAMESPACE:-swa-system}" deploy/swa-server --tail=150 > "$ARTIFACTS_DIR/swa-server.log" || true
kubectl logs -n "${SWA_NAMESPACE:-swa-system}" daemonset/swa-agent --tail=150 > "$ARTIFACTS_DIR/swa-agent.log" || true
kubectl logs -n "$NAMESPACE_HARDCODED" deploy/giftapp-hardcoded --tail=150 > "$ARTIFACTS_DIR/giftapp-hardcoded.log" || true
kubectl logs -n "$NAMESPACE_SWA" deploy/giftapp-swa --tail=150 > "$ARTIFACTS_DIR/giftapp-swa.log" || true

printf "\nTest run completed successfully.\n"
printf "Artifacts: %s\n" "$ARTIFACTS_DIR"
