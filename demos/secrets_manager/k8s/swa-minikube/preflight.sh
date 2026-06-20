#!/usr/bin/env bash
# Pre-demo warm-up. Safe to run anytime (manually or scheduled):
#   - heals the SWA control plane if degraded (e.g. expired server cert after the
#     laptop slept, which stops the agent minting SVIDs and crash-loops the pod)
#   - refreshes the workload so the first demo run is instant (fresh JWT-SVID)
#   - verifies end-to-end secret retrieval
#
# Schedule it ~1h before a demo (keeps the Mac awake for the wait):
#   nohup caffeinate -i bash -c 'sleep 3600; cd "'"$PWD"'" && bash preflight.sh \
#     >/tmp/swa_preflight.log 2>&1' >/dev/null 2>&1 &
set -uo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init >/dev/null 2>&1 || { echo "[FAIL] could not load setup/vars.env"; exit 1; }

rc=0
ok()   { printf '[OK]   %s\n' "$1"; }
info() { printf '[INFO] %s\n' "$1"; }
bad()  { printf '[FAIL] %s\n' "$1"; rc=1; }

printf '\n========== SWA preflight (heal + warm) — %s ==========\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"

if ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
  bad "Kubernetes API unreachable — start minikube (minikube start)"
  printf '\n========== NOT READY ==========\n\n'
  exit 1
fi
ok "Kubernetes API reachable ($(kubectl config current-context 2>/dev/null || echo '?'))"

# 1) Control plane: heal if the cert expired / agent not ready.
if swa_control_plane_healthy; then
  ok "SWA control plane healthy (server + agent ready, no cert errors)"
else
  info "Control plane degraded (likely expired cert after sleep) — healing (~60s)"
  swa_heal_control_plane
  if swa_control_plane_healthy; then
    ok "Control plane recovered"
  else
    bad "Control plane still degraded — check: kubectl logs -n $SWA_NAMESPACE ds/swa-agent"
  fi
fi

# 2) Warm the workload so the first demo run shows a live retrieval immediately.
info "Refreshing workload for a fresh JWT-SVID..."
swa_refresh_workload_svid swa-demo-app || true
retrieved() {
  kubectl logs -n "$SWA_APP_NAMESPACE" deploy/swa-demo-app -c app --tail="${1:-10}" 2>/dev/null \
    | grep -q "retrieved via SWA"
}
i=0
while [ "$i" -lt 12 ]; do
  retrieved 5 && break
  sleep 5; i=$((i + 1))
done
if retrieved 5; then
  ok "Workload retrieving secrets via JWT-SVID — demo is warm"
else
  bad "Workload not retrieving yet — check: kubectl logs -n $SWA_APP_NAMESPACE deploy/swa-demo-app -c app"
fi

# 3) Optional components (non-fatal).
if kubectl get deploy/spiffe-info -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1; then
  ok "spiffe-info inspector deployed"
else
  info "spiffe-info not deployed — bash setup/swa/deploy_spiffe_info.sh"
fi
if kubectl get deploy/acme-carrier -n acme-external >/dev/null 2>&1; then
  ok "acme-carrier (trust-boundary beat) deployed"
else
  info "acme-carrier not deployed — bash setup/swa/deploy_acme.sh"
fi

printf '\n'
[[ $rc -eq 0 ]] && printf '========== READY — run: bash demo.sh ==========\n\n' \
               || printf '========== NOT READY — see [FAIL] above ==========\n\n'
exit $rc
