#!/usr/bin/env bash
# Pass/fail readiness check before presenting the SWA demo.
set -uo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init >/dev/null 2>&1 || { echo "[FAIL] could not load setup/vars.env"; exit 1; }

rc=0
ok()   { printf '[OK]   %s\n' "$1"; }
bad()  { printf '[FAIL] %s\n' "$1"; rc=1; }

printf '\n========== SWA demo — readiness ==========\n\n'

# SWA Server
if kubectl get deploy/swa-server -n "$SWA_NAMESPACE" >/dev/null 2>&1 \
   && [[ "$(kubectl get deploy/swa-server -n "$SWA_NAMESPACE" -o jsonpath='{.status.readyReplicas}')" == "1" ]]; then
  ok "SWA Server ready (deploy/swa-server in $SWA_NAMESPACE)"
else
  bad "SWA Server not ready in $SWA_NAMESPACE"
fi

# SWA Agent DaemonSet
desired="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
readyd="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
if [[ "${desired:-0}" -gt 0 && "${readyd:-0}" == "${desired:-0}" ]]; then
  ok "SWA Agent ready ($readyd/$desired nodes)"
else
  bad "SWA Agent not ready ($readyd/${desired:-0})"
fi

# Workload pod
if kubectl get deploy/swa-demo-app -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1 \
   && [[ "$(kubectl get deploy/swa-demo-app -n "$SWA_APP_NAMESPACE" -o jsonpath='{.status.readyReplicas}')" == "1" ]]; then
  ok "Workload running (deploy/swa-demo-app in $SWA_APP_NAMESPACE)"
else
  bad "Workload not ready in $SWA_APP_NAMESPACE"
fi

# Secret retrieval visible in logs. The init container fetches a short-lived
# SVID once; if it has aged out, refresh the workload and re-check.
retrieved() {
  kubectl logs -n "$SWA_APP_NAMESPACE" deploy/swa-demo-app -c app --tail="${1:-20}" 2>/dev/null \
    | grep -q "retrieved via SWA JWT-SVID"
}
if retrieved 20; then
  ok "Workload retrieved a secret via JWT-SVID"
elif kubectl get deploy/swa-demo-app -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1; then
  printf '       refreshing workload SVID (init-fetched SVID may have expired)...\n'
  kubectl rollout restart deployment/swa-demo-app -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1
  kubectl rollout status deployment/swa-demo-app -n "$SWA_APP_NAMESPACE" --timeout=120s >/dev/null 2>&1
  i=0
  while [ "$i" -lt 12 ]; do
    if retrieved 5; then break; fi
    sleep 5
    i=$((i + 1))
  done
  if retrieved 5; then
    ok "Workload retrieved a secret via JWT-SVID (after refresh)"
  else
    bad "No successful secret retrieval (check: kubectl logs -n $SWA_APP_NAMESPACE deploy/swa-demo-app -c app)"
  fi
else
  bad "Workload deployment not found (run: bash go.sh)"
fi

printf '\n'
[[ $rc -eq 0 ]] && printf '========== READY — run: bash demo.sh ==========\n\n' \
               || printf '========== NOT READY — see [FAIL] above ==========\n\n'
exit $rc
