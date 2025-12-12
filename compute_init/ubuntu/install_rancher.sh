#!/bin/bash
set -euo pipefail

# Install Rancher
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE=server sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

sudo cat /etc/rancher/rke2/rke2.yaml


# server: https://<PUBLIC_IP>:6443
# server: https://127.0.0.1:6443


mkdir -p ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config

kubectl get nodes
kubectl get pods -A


# You must configure RKE2 JWKS with your own issuer to expose: /openid/v1/jwks

/etc/rancher/rke2/config.yaml:

## For testing internal-only:
#kube-apiserver-arg:
#  - "service-account-issuer=https://kubernetes.default.svc"
#  - "service-account-jwks-uri=https://kubernetes.default.svc/openid/v1/jwks"

sudo systemctl restart rke2-server

# JWKS retrieval becomes but needs token auth:
#### for Rnachr Use Public Key for POCs, in prod a pass throuh service might be used with below to expose jwks without auth
# curl -s https://127.0.0.1/openid/v1/jwks

# v1.24+ style token
TOKEN=$(kubectl create token default) && curl -sk -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc:6443/openid/v1/jwks | jq .

# Checks verify JWKS:
kubectl get nodes
kubectl get --raw /.well-known/openid-configuration || echo "no discovery"
kubectl get --raw /openid/v1/jwks || echo "no jwks"
kubectl get --raw /openid/v1/jwks | jq .

kubectl get --raw /.well-known/openid-configuration | jq .
kubectl get --raw /openid/v1/jwks | jq .

kubectl get --raw "https://rke2-api.yourdomain.com:6443/openid/v1/jwks" --insecure-skip-tls-verify | jq .
