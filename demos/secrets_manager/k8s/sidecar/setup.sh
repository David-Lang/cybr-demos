#!/bin/bash
# Setup: CyberArk Secrets Provider for K8s — sidecar mode
set -euo pipefail

trap 'rc=$?; echo "[ERROR] line $LINENO: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="sp-sidecar"

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"

echo "[INFO] Setting up Secrets Provider sidecar demo"
echo "[INFO] CYBR_DEMOS_PATH=$CYBR_DEMOS_PATH"
echo "[INFO] DEMO_DIR=$DEMO_DIR"

if [[ -f "$CYBR_DEMOS_PATH/demos/setup_env.sh" ]]; then
  # shellcheck source=/dev/null
  source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
fi

SM_AUTHN_ID="${SM_AUTHN_ID:-zg-eso}"
if [[ -z "${TENANT_SUBDOMAIN:-}" ]]; then
  echo "[ERROR] TENANT_SUBDOMAIN is not set. Source demos/tenant_vars.sh or demos/setup_env.sh first."
  exit 1
fi

export TENANT_SUBDOMAIN SM_AUTHN_ID

# Minikube (and other local clusters) use a different JWKS than Rancher lab nodes.
# Point the shared JWT authenticator at this cluster when the current context is minikube.
sync_jwt_authenticator_for_current_cluster() {
  local conjur_token="$1"
  local ctx jwks validation_value issuer

  ctx=$(kubectl config current-context 2>/dev/null || true)
  if [[ "$ctx" != minikube ]]; then
    return 0
  fi

  if ! kubectl get --raw /openid/v1/jwks >/dev/null 2>&1; then
    echo "[WARN] minikube context but /openid/v1/jwks unavailable — skipping JWKS sync"
    return 0
  fi

  echo "[INFO] minikube detected — updating authn-jwt/${SM_AUTHN_ID} public-keys for this cluster"
  jwks=$(kubectl get --raw /openid/v1/jwks)
  validation_value=$(jq -cn --argjson jwks "$jwks" '{type:"jwks", value:$jwks}')
  issuer=$(kubectl create token sp-sidecar-sa -n sp-sidecar --audience conjur --duration 60s 2>/dev/null \
    | python3 -c "import sys,json,base64; t=sys.stdin.read().strip().split('.')[1]; t+='='*(-len(t)%4); print(json.loads(base64.urlsafe_b64decode(t))['iss'])" 2>/dev/null \
    || echo "https://kubernetes.default.svc.cluster.local")

  apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
    "conjur/authn-jwt/${SM_AUTHN_ID}/public-keys" "$validation_value"
  apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
    "conjur/authn-jwt/${SM_AUTHN_ID}/issuer" "$issuer"
  echo "[INFO] JWT authenticator issuer set to: $issuer"
  echo "[NOTE] Re-run k8s/setup/k8s/init_rancher.sh to restore Rancher JWKS when switching back to the lab cluster."
}

echo "[INFO] Applying namespace and RBAC"
kubectl apply -f "$DEMO_DIR/namespace.yaml"
kubectl apply -f "$DEMO_DIR/service-account.yaml"
kubectl apply -f "$DEMO_DIR/rbac.yaml"

echo "[INFO] Rendering conjur-connect ConfigMap"
sm_fqdn="${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud"
conjur_ssl_certificate=$(openssl s_client -connect "${sm_fqdn}:443" -servername "$sm_fqdn" </dev/null 2>/dev/null \
  | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p')
if [[ -z "$conjur_ssl_certificate" ]]; then
  echo "[ERROR] Failed to fetch Conjur SSL certificate from ${sm_fqdn}"
  exit 1
fi
cert_file=$(mktemp)
trap 'rm -f "$cert_file"' EXIT
printf '%s\n' "$conjur_ssl_certificate" > "$cert_file"
kubectl create configmap conjur-connect -n "$NAMESPACE" \
  --from-literal="CONJUR_ACCOUNT=conjur" \
  --from-literal="CONJUR_APPLIANCE_URL=https://${sm_fqdn}/api" \
  --from-literal="CONJUR_AUTHN_URL=https://${sm_fqdn}/api/authn-jwt/${SM_AUTHN_ID}" \
  --from-literal="AUTHENTICATOR_ID=${SM_AUTHN_ID}" \
  --from-literal="CONJUR_VERSION=5" \
  --from-file="CONJUR_SSL_CERTIFICATE=${cert_file}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[INFO] Applying secret mapping and deployment"
kubectl apply -f "$DEMO_DIR/secret.yaml"

if [[ -n "${TENANT_ID:-}" && -n "${CLIENT_ID:-}" && -n "${CLIENT_SECRET:-}" ]]; then
  echo "[INFO] Obtaining CyberArk tokens"
  identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
  conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")

  sync_jwt_authenticator_for_current_cluster "$conjur_token"

  echo "[INFO] Applying Conjur policies"
  apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
    "$(cat "$DEMO_DIR/conjur-policy/1-workload.yaml")"
  apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
    "$(cat "$DEMO_DIR/conjur-policy/2-grant-safe-access.yaml")"
  apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-jwt" \
    "$(cat "$DEMO_DIR/conjur-policy/3-grant-authenticator-access.yaml")"
else
  echo "[WARN] Tenant credentials not set — skipping Conjur policy setup."
  echo "[WARN] Apply conjur-policy/*.yaml manually before the sidecar can authenticate."
fi

kubectl apply -f "$DEMO_DIR/deployment.yaml"
kubectl rollout status deployment -n "$NAMESPACE" sidecar-demo-app --timeout=180s

echo "[INFO] Waiting for sidecar to populate db-credentials..."
for _ in $(seq 1 24); do
  if kubectl get secret -n "$NAMESPACE" db-credentials -o jsonpath='{.data.username}' 2>/dev/null | grep -q .; then
    echo "[INFO] Secret db-credentials is populated"
    break
  fi
  sleep 5
done

kubectl get secret -n "$NAMESPACE" db-credentials -o wide 2>/dev/null || true

echo "[INFO] Restarting app so secretKeyRef env vars pick up populated keys"
kubectl rollout restart deployment -n "$NAMESPACE" sidecar-demo-app
kubectl rollout status deployment -n "$NAMESPACE" sidecar-demo-app --timeout=120s

echo "[INFO] Setup complete — run: bash $DEMO_DIR/demo.sh"
