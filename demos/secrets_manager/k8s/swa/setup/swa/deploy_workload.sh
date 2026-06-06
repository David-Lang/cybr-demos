#!/bin/bash
# Render + apply the demo workload (namespace, service account, deployment). Idempotent.
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init
swa_release_paths

wl="$demo_path/workload"
export SWA_IMG_AGENT

echo "[INFO] Applying workload namespace + service account"
kubectl apply -f "$wl/namespace.yaml"
kubectl apply -f "$wl/serviceaccount.yaml"

echo "[INFO] Rendering + applying workload deployment"
resolve_template "$wl/deployment.tmpl.yaml" "$wl/deployment.yaml"
kubectl apply -f "$wl/deployment.yaml"

kubectl rollout status deployment/swa-demo-app -n "$SWA_APP_NAMESPACE" --timeout=180s || true
echo "[INFO] Workload deployed. Tail logs with:"
echo "       kubectl logs -n $SWA_APP_NAMESPACE deploy/swa-demo-app -f"
