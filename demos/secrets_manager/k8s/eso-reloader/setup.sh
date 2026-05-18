#!/bin/bash
# Setup: Auto-Rotate K8s Secrets — ESO + CyberArk Conjur Cloud
# Deploys ESO resources, Conjur policies, a sample app, and optionally Reloader.
set -euo pipefail

trap 'rc=$?; echo "[ERROR] line $LINENO: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="eso-reloader"

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"

echo "[INFO] Setting up ESO Auto-Rotation Demo"
echo "[INFO] CYBR_DEMOS_PATH=$CYBR_DEMOS_PATH"
echo "[INFO] DEMO_DIR=$DEMO_DIR"

# ── Source shared environment ────────────────────────────
if [[ -f "$CYBR_DEMOS_PATH/demos/setup_env.sh" ]]; then
  # shellcheck source=/dev/null
  source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
fi

# ── Verify ESO is installed ─────────────────────────────
echo "[INFO] Checking ESO installation"
if ! kubectl get deployment -n external-secrets external-secrets &>/dev/null; then
  echo "[INFO] ESO not found — installing via Helm"
  helm repo add external-secrets https://charts.external-secrets.io
  helm repo update external-secrets
  helm install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace --set installCRDs=true
  kubectl rollout status deployment -n external-secrets external-secrets --timeout=120s
  kubectl rollout status deployment -n external-secrets external-secrets-webhook --timeout=120s
  kubectl rollout status deployment -n external-secrets external-secrets-cert-controller --timeout=120s
else
  echo "[INFO] ESO already installed"
fi

# ── Install Reloader (before anything that might fail) ──
if ! kubectl get deployment -A -l app.kubernetes.io/name=reloader -o name 2>/dev/null | grep -q .; then
  echo "[INFO] Reloader not found — installing via Helm"
  helm repo add stakater https://stakater.github.io/stakater-charts
  helm repo update stakater
  helm install reloader stakater/reloader -n reloader --create-namespace
  kubectl rollout status deployment -n reloader reloader-reloader --timeout=60s
  echo "[INFO] Reloader installed — will auto-restart pods on secret changes"
else
  echo "[INFO] Reloader already installed"
fi

# ── Apply K8s manifests ──────────────────────────────────
echo "[INFO] Creating namespace and K8s resources"
kubectl apply -f "$DEMO_DIR/namespace.yaml"
kubectl apply -f "$DEMO_DIR/service-account.yaml"

# ── Apply Conjur policies ────────────────────────────────
if [[ -n "${TENANT_ID:-}" && -n "${CLIENT_ID:-}" && -n "${CLIENT_SECRET:-}" ]]; then
  echo "[INFO] Obtaining CyberArk tokens"
  identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
  conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")

  echo "[INFO] Applying Conjur policies"

  echo "[INFO]   1-workload.yaml → data"
  apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
    "$(cat "$DEMO_DIR/conjur-policy/1-workload.yaml")"

  echo "[INFO]   2-grant-safe-access.yaml → data"
  apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
    "$(cat "$DEMO_DIR/conjur-policy/2-grant-safe-access.yaml")"

  echo "[INFO]   3-grant-authenticator-access.yaml → conjur/authn-jwt"
  apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-jwt" \
    "$(cat "$DEMO_DIR/conjur-policy/3-grant-authenticator-access.yaml")"
else
  echo "[WARN] Tenant credentials not set — skipping Conjur policy setup."
  echo "[WARN] Set TENANT_ID, CLIENT_ID, CLIENT_SECRET, and TENANT_SUBDOMAIN"
  echo "[WARN] or apply the policies in conjur-policy/ manually."
fi

# ── Apply ESO resources ──────────────────────────────────
echo "[INFO] Applying SecretStore and ExternalSecret"
kubectl apply -f "$DEMO_DIR/secretstore.yaml"
kubectl apply -f "$DEMO_DIR/externalsecret.yaml"

echo "[INFO] Waiting for ExternalSecret to sync..."
sleep 5
kubectl get externalsecret -n "$NAMESPACE" db-credentials -o wide

# ── Deploy sample application ────────────────────────────
echo "[INFO] Deploying sample application"
kubectl apply -f "$DEMO_DIR/deployment.yaml"
kubectl rollout status deployment -n "$NAMESPACE" rotation-demo-app --timeout=120s

echo "[INFO] Setup complete"
echo "[INFO] Run the demo: bash $DEMO_DIR/demo.sh"
