#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
TF_DIR="$SCRIPT_DIR/terraform"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

required_vars=(
  TENANT_SUBDOMAIN TENANT_ID CLIENT_ID CLIENT_SECRET
  SWA_CONTAINER_IMAGES_S3 SWA_TF_PROVIDER_S3 SWA_HELM_CHARTS_S3
  SWA_TRUST_DOMAIN_NAME SWA_RESOURCE_PREFIX SWA_NODE_GROUP_NAME
  SWA_CLUSTER_NAME SWA_NAMESPACE JWT_SWA_SERVER_SUBJECT
  NAMESPACE_SWA GIFTAPP_SWA_SERVICE_ACCOUNT
)
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]] || [[ "${!var_name}" == SET_* ]]; then
    echo "[ERROR] $var_name is not set" >&2
    exit 1
  fi
done

for cmd in aws helm jq kubectl terraform; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[ERROR] required command not found: $cmd" >&2
    exit 1
  }
done

chmod +x \
  "$SCRIPT_DIR/install_tf_provider.sh" \
  "$SCRIPT_DIR/import_container_images.sh" \
  "$SCRIPT_DIR/write_registration_env.sh"

helm_chart() {
  local name="$1"
  local chart_name="${name}-0.1.0.tgz"
  local cache_dir
  if [[ -n "${SWA_HELM_CHARTS_CACHE_DIR:-}" ]]; then
    cache_dir="$SWA_HELM_CHARTS_CACHE_DIR"
  elif [[ -n "${SWA_RELEASE_S3:-}" ]]; then
    cache_dir="/tmp/${SWA_RELEASE_S3##*/}/helm"
  else
    cache_dir="/tmp/swa-helm-charts"
  fi
  local cached_chart="$cache_dir/$chart_name"

  if [[ -z "${SWA_HELM_CHARTS_S3:-}" ]]; then
    echo "[ERROR] SWA_HELM_CHARTS_S3 is required; set SWA_RELEASE_S3 or SWA_HELM_CHARTS_S3" >&2
    exit 1
  fi

  mkdir -p "$cache_dir"
  if [[ ! -f "$cached_chart" ]]; then
    echo "[INFO] downloading Helm chart $chart_name from ${SWA_HELM_CHARTS_S3%/}" >&2
    aws s3 cp --no-progress "${SWA_HELM_CHARTS_S3%/}/$chart_name" "$cached_chart" >&2
  else
    echo "[INFO] Helm chart already exists: $cached_chart" >&2
  fi
  printf '%s\n' "$cached_chart"
}

echo "[INFO] installing SWA Terraform provider"
bash "$SCRIPT_DIR/install_tf_provider.sh"

echo "[INFO] importing SWA container images from $SWA_CONTAINER_IMAGES_S3"
bash "$SCRIPT_DIR/import_container_images.sh"
source "$SCRIPT_DIR/swa_images.env"

echo "[INFO] reading Kubernetes OIDC metadata"
K8S_ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)
K8S_JWKS_URI="${K8S_JWKS_URI:-$K8S_ISSUER/openid/v1/jwks}"
K8S_PUBLIC_KEYS_FOR_TF=$(kubectl get --raw /openid/v1/jwks | jq -c '{type:"jwks", value:.}')

echo "[INFO] authenticating to Secrets Manager for Terraform provider"
identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")
conjur_url="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
control_plane_url="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud"

echo "[INFO] applying SWA control-plane Terraform"
terraform -chdir="$TF_DIR" init -upgrade
terraform -chdir="$TF_DIR" apply \
  -var="conjur_url=$conjur_url" \
  -var="conjur_token=$conjur_token" \
  -var="trust_domain_name=$SWA_TRUST_DOMAIN_NAME" \
  -var="resource_prefix=$SWA_RESOURCE_PREFIX" \
  -var="node_group_name=$SWA_NODE_GROUP_NAME" \
  -var="cluster_name=$SWA_CLUSTER_NAME" \
  -var="swa_namespace=$SWA_NAMESPACE" \
  -var="k8s_public_keys=$K8S_PUBLIC_KEYS_FOR_TF" \
  -var="k8s_issuer=$K8S_ISSUER" \
  -var="k8s_jwks_uri=$K8S_JWKS_URI" \
  -var="server_jwt_subject=$JWT_SWA_SERVER_SUBJECT" \
  -var="workload_namespace=$NAMESPACE_SWA" \
  -var="workload_service_account=$GIFTAPP_SWA_SERVICE_ACCOUNT" \
  -auto-approve

bash "$SCRIPT_DIR/write_registration_env.sh"
source "$SCRIPT_DIR/swa_registered.env"

server_auth_svc=$(printf '%s' "$SWA_SERVER_LOGIN_URL" | base64 -d 2>/dev/null | grep -o 'authn-jwt/[^/]*' | head -1 || true)
if [[ -n "$server_auth_svc" ]]; then
  echo "[INFO] enabling SWA Server authenticator: $server_auth_svc"
  activate_conjur_service "$TENANT_SUBDOMAIN" "$conjur_token" "$server_auth_svc" >/dev/null
else
  echo "[WARN] could not extract SWA Server authenticator name from Terraform login URL" >&2
fi

server_chart=$(helm_chart "swa-server")
agent_chart=$(helm_chart "swa-agent")

echo "[INFO] installing SWA Server Helm release"
helm upgrade --install swa-server "$server_chart" \
  --namespace "$SWA_NAMESPACE" \
  --create-namespace \
  --set-string "image.repository=$SWA_SERVER_IMAGE_REPOSITORY" \
  --set-string "image.tag=$SWA_IMAGE_TAG" \
  --set-string "image.pullPolicy=IfNotPresent" \
  --set-string "trustDomain.name=$SWA_TRUST_DOMAIN_NAME" \
  --set-string "controlPlane.url=$control_plane_url" \
  --set-string "controlPlane.auth.loginURL=$SWA_SERVER_LOGIN_URL" \
  --set-string "controlPlane.auth.tokenPath=/var/run/secrets/tokens/swa-token" \
  --set-string "controlPlane.auth.audience=conjur" \
  --set "rbac.createTokenReviewRole=true" \
  --wait --timeout 5m

echo "[INFO] installing SWA Agent Helm release"
helm upgrade --install swa-agent "$agent_chart" \
  --namespace "$SWA_NAMESPACE" \
  --set-string "image.repository=$SWA_AGENT_IMAGE_REPOSITORY" \
  --set-string "image.tag=$SWA_IMAGE_TAG" \
  --set-string "image.pullPolicy=IfNotPresent" \
  --set-string "trustDomain.name=$SWA_TRUST_DOMAIN_NAME" \
  --set-string "server.address=swa-server.$SWA_NAMESPACE.svc.cluster.local:8443" \
  --set-string "nodeAttestor.type=k8s_psat" \
  --set-string "nodeAttestor.k8s_psat.cluster=$SWA_CLUSTER_NAME" \
  --set-string "nodeAttestor.k8s_psat.audience=spire-server" \
  --set-string "podLabels.swa_nodegroup=$SWA_NODE_GROUP_NAME" \
  --set "securityContext.runAsUser=0" \
  --set "securityContext.runAsGroup=0" \
  --set "securityContext.privileged=true" \
  --set "securityContext.allowPrivilegeEscalation=true" \
  --wait --timeout 5m

echo "[INFO] SWA Helm install complete"
kubectl get pods -n "$SWA_NAMESPACE"
