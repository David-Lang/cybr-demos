#!/bin/bash
# Teardown for the SWA demo: workload, helm releases, namespaces, terraform objects, safe.
set -uo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init
swa_release_paths

echo "[INFO] Removing demo workload"
kubectl delete -f "$demo_path/workload/deployment.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete deploy/swa-demo-app -n "$SWA_APP_NAMESPACE" --ignore-not-found 2>/dev/null || true

echo "[INFO] Uninstalling helm releases"
helm uninstall swa-agent -n "$SWA_NAMESPACE" 2>/dev/null || true
helm uninstall swa-server -n "$SWA_NAMESPACE" 2>/dev/null || true

echo "[INFO] Deleting namespaces"
kubectl delete ns "$SWA_APP_NAMESPACE" --ignore-not-found 2>/dev/null || true
kubectl delete ns "$SWA_NAMESPACE" --ignore-not-found 2>/dev/null || true
# Ephemeral imposter namespace created by the red-team step in demo.sh.
kubectl delete ns swa-rogue --ignore-not-found 2>/dev/null || true

echo "[INFO] Destroying SWA control-plane objects (terraform)"
tf_dir="$demo_path/setup/swa/terraform"
if [[ -f "$tf_dir/terraform.tfstate" && -f "$SWA_TFRC" ]]; then
  if swa_get_tokens; then
    export CONJUR_APPLIANCE_URL="https://${SM_FQDN}/api"
    export CONJUR_ACCOUNT="conjur"
    conjur_authn_token="$(printf '%s' "$SWA_CONJUR_TOKEN" | base64 --decode)"
    export CONJUR_AUTHN_TOKEN="$conjur_authn_token"
    export TF_CLI_CONFIG_FILE="$SWA_TFRC"
    terraform -chdir="$tf_dir" destroy -input=false -auto-approve || \
      echo "[WARN] terraform destroy failed — remove the trust domain/server group manually."
  fi
else
  echo "[WARN] No terraform state / provider mirror — skipping terraform destroy."
fi

echo "[INFO] Deleting Privilege Cloud safe '$SAFE_NAME'"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET" 2>/dev/null || true)"
if [[ -n "$identity_token" ]]; then
  delete_account_ssh_user_1 "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" 2>/dev/null || true
  delete_safe "$TENANT_SUBDOMAIN" "$identity_token" "$SAFE_NAME" 2>/dev/null || true
fi

echo
echo "[INFO] Teardown complete."
echo "[NOTE] The Conjur authn-jwt/$SWA_AUTHN_ID authenticator and data/poc-workloads host"
echo "       remain (append-policy). Remove via the Conjur UI/policy if desired."
