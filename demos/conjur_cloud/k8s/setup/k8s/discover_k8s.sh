#!/bin/bash
set -euo pipefail

echo "# Discovering Kubernetes OIDC configuration..."

# Get the discovery document
discovery="$(kubectl get --raw /.well-known/openid-configuration)"

issuer="$(echo "$discovery" | jq -r '.issuer')"
jwks_uri="$(echo "$discovery" | jq -r '.jwks_uri')"
jwks="$(kubectl get --raw /openid/v1/jwks)"

# Write out .env file
cat <<EOF > authn_secrets.env
ISSUER=$issuer
JWKS_URI=$jwks_uri
JWKS=$jwks
EOF

echo "# Wrote authn_secrets.env"
cat authn_secrets.env

echo "# To curl the jwks uri: curl -kv $jwks_uri"

echo "# For Rancher(add port to uri :6443): token=\$(kubectl create token default) && curl -sk -H \"Authorization: Bearer \$token\" $jwks_uri && echo"
