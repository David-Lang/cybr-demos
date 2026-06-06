#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
charts_dir="$demo_path/setup/k8s/charts"

set -a
source "$demo_path/setup/vars.env"
if [[ -f "$demo_path/setup/k8s/giftapp_images.env" ]]; then
  source "$demo_path/setup/k8s/giftapp_images.env"
fi
set +a

: "${GIFTAPP_REGISTRY:?GIFTAPP_REGISTRY is not set in vars.env}"
: "${SWA_NAMESPACE:?SWA_NAMESPACE is not set}"

sm_fqdn="$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud"

printf "NAMESPACE_HARDCODED=%s\n" "$NAMESPACE_HARDCODED"
printf "NAMESPACE_SWA=%s\n" "$NAMESPACE_SWA"
printf "GIFTAPP_REGISTRY=%s\n" "$GIFTAPP_REGISTRY"
printf "SM_API_KEY_ID=%s\n" "$SM_API_KEY_ID"
printf "SM_DB_PASS_ID=%s\n" "$SM_DB_PASS_ID"

# ── giftapp-hardcoded ──────────────────────────────────────────────────────
printf "\n\nDeploying mysql-hardcoded\n"
kubectl create namespace "$NAMESPACE_HARDCODED" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install mysql-hardcoded "$charts_dir/mysql-hardcoded" \
  --namespace "$NAMESPACE_HARDCODED" \
  --set-string "mysql.appUser=$DB_USER" \
  --set-string "mysql.appPassword=$DB_PASS" \
  --wait --timeout 3m

printf "\nDeploying giftapp-hardcoded\n"
helm upgrade --install giftapp-hardcoded "$charts_dir/giftapp-hardcoded" \
  --namespace "$NAMESPACE_HARDCODED" \
  --set "image.repository=${GIFTAPP_REGISTRY%/}/giftapp-hardcoded" \
  --set "image.tag=${GIFTAPP_IMAGE_TAG:-latest}" \
  --set-string "image.pullPolicy=IfNotPresent" \
  --set-string "secrets.db.user=$DB_USER" \
  --set-string "secrets.db.pass=$DB_PASS" \
  --set-string "secrets.giftappApiKey=$GIFTAPP_API_KEY" \
  --wait --timeout 3m

# ── giftapp-swa ────────────────────────────────────────────────────────────
printf "\n\nDeploying mysql-swa\n"
kubectl create namespace "$NAMESPACE_SWA" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install mysql-swa "$charts_dir/mysql-swa" \
  --namespace "$NAMESPACE_SWA" \
  --set-string "mysql.appUser=$DB_USER" \
  --set-string "mysql.appPassword=$DB_PASS" \
  --wait --timeout 3m

printf "\nDeploying giftapp-swa\n"
helm upgrade --install giftapp-swa "$charts_dir/giftapp-swa" \
  --namespace "$NAMESPACE_SWA" \
  --set "image.repository=${GIFTAPP_REGISTRY%/}/giftapp-swa" \
  --set "image.tag=${GIFTAPP_IMAGE_TAG:-latest}" \
  --set-string "image.pullPolicy=IfNotPresent" \
  --set-string "secrets.db.user=$DB_USER" \
  --set-string "conjur.applianceUrl=https://$sm_fqdn/api" \
  --set-string "conjur.account=conjur" \
  --set-string "conjur.authenticatorId=authn-jwt/$SM_SERVICE_NAME-swa" \
  --set-string "conjur.apiKeySecretId=$SM_API_KEY_ID" \
  --set-string "conjur.dbPassSecretId=$SM_DB_PASS_ID" \
  --set-string "swa.socketPath=unix://$SWA_SOCKET_PATH" \
  --set-string "swa.socketHostPath=${SWA_SOCKET_HOST_PATH:-${SWA_SOCKET_PATH%/*}}" \
  --set "securityContext.runAsUser=${GIFTAPP_SWA_UID:-1000}" \
  --wait --timeout 3m

printf "\n\nDeploy complete\n"
kubectl get pods -n "$NAMESPACE_HARDCODED"
kubectl get pods -n "$NAMESPACE_SWA"
