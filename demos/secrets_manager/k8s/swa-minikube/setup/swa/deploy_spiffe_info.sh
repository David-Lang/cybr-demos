#!/bin/bash
# Deploy the optional spiffe-info inspector (JWT / X.509-SVID / trust bundle UI).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init

manifest="$demo_path/workload/spiffe-info.yaml"

echo "[INFO] Applying spiffe-info (namespace must exist — run deploy_workload.sh first if needed)"
kubectl apply -f "$demo_path/workload/namespace.yaml"
kubectl apply -f "$manifest"
kubectl rollout status deployment/spiffe-info -n "$SWA_APP_NAMESPACE" --timeout=120s

echo "[INFO] spiffe-info ready."
echo "       kubectl port-forward -n $SWA_APP_NAMESPACE svc/spiffe-info 8080:80"
echo "       open http://localhost:8080"
