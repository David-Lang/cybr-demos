#!/bin/bash
# Render swa-server values and helm upgrade --install. Idempotent.
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init
swa_release_paths

tf_out="$demo_path/setup/swa/terraform/swa_outputs.env"
[[ -f "$tf_out" ]] || { echo "[ERROR] $tf_out missing — run setup/swa/register.sh first." >&2; exit 1; }
# shellcheck source=/dev/null
source "$tf_out"
[[ -n "${SWA_SERVER_AUTHN_ID:-}" ]] || { echo "[ERROR] SWA_SERVER_AUTHN_ID empty in $tf_out" >&2; exit 1; }

# Split "repo:tag" into chart values.
export SWA_IMG_SERVER_REPO="${SWA_IMG_SERVER%%:*}"
export SWA_IMG_SERVER_TAGONLY="${SWA_IMG_SERVER##*:}"
export SWA_SERVER_AUTHN_ID

values_tmpl="$demo_path/setup/swa/values-swa-server.yaml.tmpl"
values_out="$demo_path/setup/swa/values-swa-server.yaml"
resolve_template "$values_tmpl" "$values_out"

echo "[INFO] Ensuring namespace $SWA_NAMESPACE"
kubectl get ns "$SWA_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$SWA_NAMESPACE"

echo "[INFO] helm upgrade --install swa-server"
helm upgrade --install swa-server "$SWA_CHART_SERVER" \
  --namespace "$SWA_NAMESPACE" \
  --values "$values_out" \
  --wait --timeout 5m

kubectl rollout status deployment/swa-server -n "$SWA_NAMESPACE" --timeout=180s
echo "[INFO] swa-server installed."
