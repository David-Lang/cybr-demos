#!/usr/bin/env bash
# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.0 \
  --set crds.enabled=true

resolve_template "letsencrypt_issuer.tmpl.yaml" "letsencrypt_issuer.yaml"
kubectl apply -f letsencrypt_issuer.yaml
