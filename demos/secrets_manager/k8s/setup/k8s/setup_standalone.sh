#!/bin/bash
set -euo pipefail

# ==============================================================================
# STANDALONE K8s DEPLOY (Helm only)
#
# Deploys the demo Helm workloads (External Secrets Operator + the poc-sm chart)
# WITHOUT performing any CyberArk Identity / Conjur / Secrets Manager tenant-side
# configuration. Use this when the SM authenticator, safes, and workloads have
# already been configured out-of-band and you only need the in-cluster deploy.
#
# This script is self-contained: it does NOT source setup_env.sh or vars.env.
# Fill in the CONFIG block below, then run it against your target kube context.
#
# Prereqs: kubectl (pointed at the target cluster), helm, openssl, base64.
# ------------------------------------------------------------------------------
# CONFIG - fill these in
# ------------------------------------------------------------------------------

# CyberArk Secrets Manager SaaS tenant subdomain (e.g. "my-tenant").
# The SM FQDN is derived as: <subdomain>.secretsmgr.cyberark.cloud
TENANT_SUBDOMAIN=""

# The SM JWT authenticator / service name. Also used as the deployed namespace.
SM_SERVICE_NAME=""

# Kubernetes service account the workloads authenticate as.
SM_APP_SERVICE_ACCOUNT="poc-service-account"

# Secret IDs (paths in Secrets Manager) and the var names to expose in K8s.
SM_SECRET_1_ID="data/vault/${SM_SERVICE_NAME}/account-ssh-user-1/username"
SM_SECRET_1_NAME="username"
SM_SECRET_2_ID="data/vault/${SM_SERVICE_NAME}/account-ssh-user-1/password"
SM_SECRET_2_NAME="password"

# Path to the poc-sm Helm chart. Defaults to this script's sibling chart dir.
CHART_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/charts/poc-sm"

# ==============================================================================
# Do not edit below this line
# ==============================================================================

# Print failing command + line number
rc=0
trap 'rc=$?; echo "[ERROR] line $LINENO: command failed: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

sm_fqdn="$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud"

# ------------------------------------------------------------------------------
# Validate config
# ------------------------------------------------------------------------------
[ -n "${TENANT_SUBDOMAIN:-}" ]        || { echo "[ERROR] TENANT_SUBDOMAIN is empty" >&2; exit 1; }
[ -n "${SM_SERVICE_NAME:-}" ]         || { echo "[ERROR] SM_SERVICE_NAME is empty" >&2; exit 1; }
[ -n "${SM_APP_SERVICE_ACCOUNT:-}" ]  || { echo "[ERROR] SM_APP_SERVICE_ACCOUNT is empty" >&2; exit 1; }
[ -n "${SM_SECRET_1_ID:-}" ]          || { echo "[ERROR] SM_SECRET_1_ID is empty" >&2; exit 1; }
[ -n "${SM_SECRET_1_NAME:-}" ]        || { echo "[ERROR] SM_SECRET_1_NAME is empty" >&2; exit 1; }
[ -n "${SM_SECRET_2_ID:-}" ]          || { echo "[ERROR] SM_SECRET_2_ID is empty" >&2; exit 1; }
[ -n "${SM_SECRET_2_NAME:-}" ]        || { echo "[ERROR] SM_SECRET_2_NAME is empty" >&2; exit 1; }
[ -d "$CHART_PATH" ]                  || { echo "[ERROR] chart not found: $CHART_PATH" >&2; exit 1; }

for tool in kubectl helm openssl base64; do
  command -v "$tool" >/dev/null 2>&1 || { echo "[ERROR] required tool not found: $tool" >&2; exit 1; }
done

echo "[INFO] sm_fqdn=$sm_fqdn"
echo "[INFO] sm_service_name=$SM_SERVICE_NAME"
echo "[INFO] sm_app_service_account=$SM_APP_SERVICE_ACCOUNT"
echo "[INFO] chart_path=$CHART_PATH"
echo "[INFO] kube-context=$(kubectl config current-context 2>/dev/null || echo '<none>')"

# ------------------------------------------------------------------------------
# Install External Secrets Operator
# ------------------------------------------------------------------------------

# Add/update repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install/upgrade External Secrets Operator (ESO) + its CRDs
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --timeout 10m \
  --debug \
  --wait

# Verify CRDs exist
kubectl get crd | grep -Ei 'externalsecrets\.external-secrets\.io|secretstores\.external-secrets\.io|clustersecretstores\.external-secrets\.io' \
  || echo "Missing ESO CRDs"

# Show served versions (useful when debugging mismatches)
kubectl get crd \
  externalsecrets.external-secrets.io \
  secretstores.external-secrets.io \
  clustersecretstores.external-secrets.io \
  -o 'custom-columns=NAME:.metadata.name,SERVED:.spec.versions[?(@.served==true)].name'

# Verify pods are running
kubectl -n external-secrets get pods -o wide

# Quick API visibility check (optional)
kubectl api-resources | grep -Ei 'externalsecret|secretstore|clustersecretstore' \
  || echo "ESO API resources not visible yet"

# ------------------------------------------------------------------------------
# Install Secrets Manager SaaS Use Cases (Helm)
# ------------------------------------------------------------------------------

openssl s_client -connect "$sm_fqdn:443" -servername "$sm_fqdn" </dev/null 2>/dev/null \
| sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' \
| openssl x509 -inform pem -text > sm.pem

# Helm release names do not allow '_' use '-'
helm upgrade --install poc-sm \
     "$CHART_PATH" \
     --namespace default \
     --set namespace="$SM_SERVICE_NAME" \
     --set sm_fqdn="$sm_fqdn" \
     --set sm_cert_b64="$(base64 -w0 < sm.pem)" \
     --set sm_authn_id="$SM_SERVICE_NAME" \
     --set sm_app_service_account="$SM_APP_SERVICE_ACCOUNT" \
     --set sm_secret_1_id="$SM_SECRET_1_ID" \
     --set sm_secret_1_name="$SM_SECRET_1_NAME" \
     --set sm_secret_2_id="$SM_SECRET_2_ID" \
     --set sm_secret_2_name="$SM_SECRET_2_NAME" \
     --debug

echo "[INFO] done"
