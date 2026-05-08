#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
TF_DIR="$SCRIPT_DIR/terraform"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

printf "\nUninstalling SWA Helm releases\n"
helm uninstall swa-agent -n "$SWA_NAMESPACE" 2>/dev/null || true
helm uninstall swa-server -n "$SWA_NAMESPACE" 2>/dev/null || true

if [[ -d "$TF_DIR" ]]; then
  identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
  conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")
  conjur_url="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
  K8S_ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)
  K8S_JWKS_URI="${K8S_JWKS_URI:-$K8S_ISSUER/openid/v1/jwks}"
  K8S_PUBLIC_KEYS_FOR_TF=$(kubectl get --raw /openid/v1/jwks | jq -c '{type:"jwks", value:.}')

  printf "\nDestroying SWA Terraform resources\n"
  terraform -chdir="$TF_DIR" destroy \
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
    -auto-approve || true
fi

printf "\nSWA cleanup complete\n"
