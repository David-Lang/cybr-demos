#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
vars_file="$demo_path/setup/vars.env"

printf "\n\nDiscovering Kubernetes OIDC configuration\n"

printf "\njwks (compact):\n"
kubectl get --raw /openid/v1/jwks | jq -c . || echo "[WARN] no jwks endpoint"

printf "\nopenid-configuration:\n"
kubectl get --raw /.well-known/openid-configuration | jq . || echo "[WARN] no discovery endpoint"

# Extract JWKS as compact JSON
escaped_keys=$(kubectl get --raw /openid/v1/jwks | jq -c .)

# Write K8S_PUBLIC_KEYS into vars.env (replace existing value)
sed -i.bak "s|^K8S_PUBLIC_KEYS=.*|K8S_PUBLIC_KEYS='$escaped_keys'|" "$vars_file"

# Write K8S_JWKS_URI if accessible (EKS style)
ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer' || echo "")
if [[ -n "$ISSUER" ]]; then
  sed -i.bak "s|^K8S_JWKS_URI=.*|K8S_JWKS_URI='$ISSUER/openid/v1/jwks'|" "$vars_file"
fi

printf "\nK8S_PUBLIC_KEYS written to %s\n" "$vars_file"
