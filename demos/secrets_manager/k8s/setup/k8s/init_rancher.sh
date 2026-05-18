#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/k8s"

# For POCs use Rancher Public Key

# JWKS retrieval needs token auth:
# v1.24+ style token
# TOKEN=$(kubectl create token default) && curl -sk -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc:6443/openid/v1/jwks | jq .
# In prod a https service might be used with below to publicly expose jwks
# curl -s https://127.0.0.1/openid/v1/jwks

# Checks verify JWKS (use cluster-relative paths so kubeconfig works on any API endpoint;
# avoid hardcoded https://localhost:6443 — that only applies when the API is tunneled locally.)
printf "\n\njwks jq formated\n"
kubectl get --raw /openid/v1/jwks | jq .
printf "\n\nopenid-configurations\n"
kubectl get --raw /.well-known/openid-configuration || echo "no discovery"
printf "\n\njwks raw\n"
kubectl get --raw /openid/v1/jwks || echo "no jwks"
printf "\n\njwks jq -c\n"
kubectl get --raw /openid/v1/jwks | jq -c || echo "no jwks"

# Escape JSON for .env (quotes + newlines)
escaped_keys=$(kubectl get --raw /openid/v1/jwks | jq -c .)

vars_file="$demo_path/setup/vars.env"

# Replace placeholder or existing value
sed -i.bak "s|^K8S_PUBLIC_KEYS=.*|K8S_PUBLIC_KEYS='$escaped_keys'|" "$vars_file"
