#!/bin/bash
# Render swa-agent values and helm upgrade --install (DaemonSet). Idempotent.
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init
swa_release_paths

export SWA_IMG_AGENT_REPO="${SWA_IMG_AGENT%%:*}"
export SWA_IMG_AGENT_TAGONLY="${SWA_IMG_AGENT##*:}"
export SWA_SERVER_DNS="swa-server.${SWA_NAMESPACE}.svc.cluster.local"
export SWA_PSAT_AUDIENCE="${SWA_PSAT_AUDIENCE:-swa-server}"

values_tmpl="$demo_path/setup/swa/values-swa-agent.yaml.tmpl"
values_out="$demo_path/setup/swa/values-swa-agent.yaml"
resolve_template "$values_tmpl" "$values_out"

echo "[INFO] Ensuring namespace $SWA_NAMESPACE"
kubectl get ns "$SWA_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$SWA_NAMESPACE"

echo "[INFO] helm upgrade --install swa-agent"
helm upgrade --install swa-agent "$SWA_CHART_AGENT" \
  --namespace "$SWA_NAMESPACE" \
  --values "$values_out" \
  --wait --timeout 5m

kubectl rollout status daemonset/swa-agent -n "$SWA_NAMESPACE" --timeout=180s
echo "[INFO] swa-agent installed."
