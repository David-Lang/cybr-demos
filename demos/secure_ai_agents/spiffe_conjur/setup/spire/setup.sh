#!/bin/bash
# setup/spire/setup.sh
#
# Stage 1: stand up the local Kubernetes cluster (minikube), install SPIRE via
# Helm with the OIDC discovery provider enabled, build the spire-tools image
# into the minikube image store, and apply the ClusterSPIFFEID policy.
#
# Idempotent: re-runs cleanly. Safe to invoke directly or via top-level setup.sh.

# shellcheck disable=SC1091
set -euo pipefail

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  CYBR_DEMOS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
  export CYBR_DEMOS_PATH
fi

demo_path="$CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

stage_dir="$demo_path/setup/spire"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { printf "[FAIL] missing required command: %s\n" "$1" >&2; exit 1; }
}
require_cmd minikube
require_cmd kubectl
require_cmd helm
require_cmd docker

kctx() { kubectl --context "$MINIKUBE_PROFILE" "$@"; }

# ─── 1. Minikube ─────────────────────────────────────────────────────────────
printf "\n[INFO] SPIRE: ensuring minikube profile %s is running\n" "$MINIKUBE_PROFILE"
if ! minikube -p "$MINIKUBE_PROFILE" status >/dev/null 2>&1; then
  printf "[INFO] SPIRE: starting minikube profile %s (k8s %s, %s CPU, %s MB)\n" \
    "$MINIKUBE_PROFILE" "$MINIKUBE_K8S_VERSION" "$MINIKUBE_CPUS" "$MINIKUBE_MEMORY"
  minikube start -p "$MINIKUBE_PROFILE" \
    --kubernetes-version="$MINIKUBE_K8S_VERSION" \
    --cpus="$MINIKUBE_CPUS" \
    --memory="$MINIKUBE_MEMORY" \
    --driver="$MINIKUBE_DRIVER"
else
  printf "[INFO] SPIRE: minikube profile %s already running\n" "$MINIKUBE_PROFILE"
fi
kubectl config use-context "$MINIKUBE_PROFILE" >/dev/null

# ─── 2. SPIRE CRDs + SPIRE control plane via Helm ────────────────────────────
printf "\n[INFO] SPIRE: installing helm repo %s\n" "$SPIRE_HELM_REPO_NAME"
helm repo add "$SPIRE_HELM_REPO_NAME" "$SPIRE_HELM_REPO_URL" >/dev/null 2>&1 || true
helm repo update "$SPIRE_HELM_REPO_NAME" >/dev/null

kctx create namespace "$SPIRE_NAMESPACE" --dry-run=client -o yaml | kctx apply -f - >/dev/null

printf "[INFO] SPIRE: helm upgrade --install spire-crds (%s)\n" "$SPIRE_CRDS_VERSION"
helm upgrade --install spire-crds "$SPIRE_HELM_REPO_NAME/spire-crds" \
  --version "$SPIRE_CRDS_VERSION" \
  --namespace "$SPIRE_NAMESPACE" \
  -f "$stage_dir/helm-values/spire-crds-values.yaml" \
  --wait --timeout 5m

printf "[INFO] SPIRE: helm upgrade --install spire (%s) [trustDomain=%s]\n" "$SPIRE_VERSION" "$TRUST_DOMAIN"
helm upgrade --install spire "$SPIRE_HELM_REPO_NAME/spire" \
  --version "$SPIRE_VERSION" \
  --namespace "$SPIRE_NAMESPACE" \
  -f "$stage_dir/helm-values/spire-values.yaml" \
  --set "global.spire.trustDomain=$TRUST_DOMAIN" \
  --set "global.spire.clusterName=$MINIKUBE_PROFILE" \
  --wait --timeout 10m

kctx -n "$SPIRE_NAMESPACE" rollout status statefulset/spire-server --timeout=180s
kctx -n "$SPIRE_NAMESPACE" rollout status daemonset/spire-agent   --timeout=180s

# ─── 3. spire-tools image into the minikube image store ──────────────────────
spire_short_version="${SPIRE_TOOLS_IMAGE##*:}"
printf "\n[INFO] SPIRE: building spire-tools:%s into minikube image store\n" "$spire_short_version"
eval "$(minikube -p "$MINIKUBE_PROFILE" docker-env)"
docker build \
  --build-arg "SPIRE_VERSION=$spire_short_version" \
  -t "$SPIRE_TOOLS_IMAGE" \
  "$stage_dir/images/spire-tools"

# ─── 4. Apply our ClusterSPIFFEID policy ─────────────────────────────────────
printf "\n[INFO] SPIRE: applying ClusterSPIFFEID workloads-default\n"
kctx apply -f "$stage_dir/manifests/00-namespace.yaml"
kctx apply -f "$stage_dir/manifests/10-cluster-spiffe-ids.yaml"

printf "\n[INFO] SPIRE: stage complete (trust domain: %s)\n" "$TRUST_DOMAIN"
