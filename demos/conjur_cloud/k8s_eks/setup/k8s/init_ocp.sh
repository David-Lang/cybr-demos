#!/bin/bash
set -euo pipefail

echo "Getting K8s Info"

# -----------------------------------------------------------------------------------------------------------
# Standard K8s

# Check that the Service Account Issuer Discovery service in Kubernetes is publicly available
# If the command ran successfully and returned a valid JWKS,
# run the following command to retrieve and store the jwks-uri value from Kubernetes
# curl "$(kubectl get --raw /.well-known/openid-configuration | jq -r '.jwks_uri')" | jq

# If the command failed, the Service Account Issuer Discovery service is not publicly available.
# In this case you need to save the JWKS output to a file
# kubectl get --raw "$(kubectl get --raw /.well-known/openid-configuration | jq -r '.jwks_uri')" > jwks.json
# -----------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------
# OCP K8s
ocp_fqdn="replace.with.your.ocp.fqdn"

##OCP Notes:
##  How to execute REST API calls to OpenShift 4
oc login -u USER https://"$ocp_fqdn":6443
oc whoami
oc whoami --show-server

token=$(oc whoami -t)
project_svc_uri="https://$ocp_fqdn:6443/apis/project.openshift.io/v1/projects"
curl -s -k -H "Authorization: Bearer $token" -X GET "$project_svc_uri"

# Show full response
oc get --raw /.well-known/openid-configuration

issuer=$(oc get --raw /.well-known/openid-configuration | jq -r '.issuer')
echo "$issuer"

### pay attention to the FQDN returned from openid-configuration vs the oc login if they are different try both
jwks_svc_uri="https://$ocp_fqdn:6443/openid/v1/jwks"
# Show full response
curl -s -k -H "Authorization: Bearer $token" -X GET "$jwks_svc_uri"
public_keys="$(curl -s -k -H "Authorization: Bearer $token" -X GET "$jwks_svc_uri")"
echo "$public_keys"

rm -f authn_secrets.env
echo "ISSUER=$issuer" >> authn_secrets.env
echo "PUBLIC_KEYS=$public_keys" >> authn_secrets.env

# -----------------------------------------------------------------------------------------------------------
