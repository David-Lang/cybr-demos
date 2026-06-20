#!/bin/bash
# Deploy the foreign-trust-domain acme-carrier (trust-boundary demo beat).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
acme_dir="$demo_path/workload/acme"

echo "[INFO] Applying acme-external namespace + acme-carrier"
kubectl apply -f "$acme_dir/namespace.yaml"
kubectl apply -f "$acme_dir/deployment.yaml"
kubectl rollout status deployment/acme-carrier -n acme-external --timeout=120s
echo "[INFO] acme-carrier ready at acme-carrier.acme-external.svc.cluster.local:8443"
