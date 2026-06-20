#!/bin/bash
# Teardown for the SWA demo: workload, helm releases, terraform, namespaces, safe.
set -uo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init
swa_release_paths

echo "[INFO] Removing demo workload and optional components"
kubectl delete -f "$demo_path/workload/deployment.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete deploy/swa-demo-app -n "$SWA_APP_NAMESPACE" --ignore-not-found 2>/dev/null || true
kubectl delete -f "$demo_path/workload/spiffe-info.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete -f "$demo_path/workload/acme/deployment.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete -f "$demo_path/workload/acme/namespace.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete ns swa-rogue --ignore-not-found 2>/dev/null || true

echo "[INFO] Uninstalling helm releases"
helm uninstall swa-agent -n "$SWA_NAMESPACE" 2>/dev/null || true
helm uninstall swa-server -n "$SWA_NAMESPACE" 2>/dev/null || true

echo "[INFO] Destroying SWA control-plane objects (terraform) — before namespace delete"
tf_dir="$demo_path/setup/swa/terraform"
if [[ -f "$tf_dir/terraform.tfstate" && -f "$SWA_TFRC" ]]; then
  destroy_ok=0
  for attempt in 1 2 3; do
    echo "[INFO] terraform destroy attempt ${attempt}/3"
    if swa_get_tokens; then
      export CONJUR_APPLIANCE_URL="https://${SM_FQDN}/api"
      export CONJUR_ACCOUNT="conjur"
      conjur_authn_token="$(printf '%s' "$SWA_CONJUR_TOKEN" | base64 --decode)"
      export CONJUR_AUTHN_TOKEN="$conjur_authn_token"
      export TF_CLI_CONFIG_FILE="$SWA_TFRC"
      if terraform -chdir="$tf_dir" destroy -input=false -auto-approve -refresh=false; then
        destroy_ok=1
        break
      fi
      echo "[WARN] terraform destroy attempt ${attempt} failed (SM token may have expired)"
    else
      echo "[WARN] Could not acquire Conjur token for destroy attempt ${attempt}"
    fi
    sleep 2
  done
  remaining="$(terraform -chdir="$tf_dir" state list 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$destroy_ok" != "1" || "${remaining:-0}" != "0" ]]; then
    echo "[WARN] terraform destroy incomplete (${remaining:-?} resources remain) — remove trust domain manually"
  fi
else
  echo "[WARN] No terraform state / provider mirror — skipping terraform destroy."
fi

echo "[INFO] Deleting Kubernetes namespaces"
kubectl delete ns "$SWA_APP_NAMESPACE" --ignore-not-found 2>/dev/null || true
kubectl delete ns "$SWA_NAMESPACE" --ignore-not-found 2>/dev/null || true
kubectl delete ns acme-external --ignore-not-found 2>/dev/null || true

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
