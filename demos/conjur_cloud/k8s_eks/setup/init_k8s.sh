#!/bin/bash
set -euo pipefail

echo "Getting K8s Info"

# Check that the Service Account Issuer Discovery service in Kubernetes is publicly available
# If the command ran successfully and returned a valid JWKS,
# run the following command to retrieve and store the jwks-uri value from Kubernetes
# curl "$(kubectl get --raw /.well-known/openid-configuration | jq -r '.jwks_uri')" | jq

# If the command failed, the Service Account Issuer Discovery service is not publicly available.
# In this case you need to save the JWKS output to a file
# kubectl get --raw "$(kubectl get --raw /.well-known/openid-configuration | jq -r '.jwks_uri')" > jwks.json

# For EKS
issuer=$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer')
echo "$issuer"

public_keys="$(curl -s "$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer')"/keys)"
echo "$public_keys"

rm -f authn_secrets.env
echo "ISSUER=$issuer" >> authn_secrets.env
echo "PUBLIC_KEYS=$public_keys" >> authn_secrets.env
