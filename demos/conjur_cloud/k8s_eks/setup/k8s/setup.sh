#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/conjur_cloud/github.com"
# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
source "$demo_path/setup/vars.env"
set +a

sm_fqdn="$SM_FQDN"
sm_namespace="$NAMESPACE"

# Setup k8s

openssl s_client -connect "$sm_fqdn":443 </dev/null 2>/dev/null \
| openssl x509 -inform pem -text > sm.pem

# Setup IAM EKS Admin creds
# eks_name="<-- set" # poc-cdn
# aws configure

# Setup kubconfig
# aws eks update-kubeconfig --region ca-central-1 --name "$eks_name"


# helm repo add external-secrets https://charts.external-secrets.io
# helm install external-secrets external-secrets/external-secrets --debug
helm install sm-poc-external-secrets \
     ./setup/charts/external-secrets \
     --namespace default \
     --debug

# Helm install Release names does not allow '_' use '-'
helm install sm-poc-k8s-eks \
     ./setup/charts/sm-poc \
     --namespace default \
     --set namespace=$namespace \
     --set conjur_fqdn="$sm_fqdn" \
     --set conjur_cert_b64="$(cat sm.pem | base64 -w0 )" \
     --set conjur_authn_id="k8s-eks-1" \
     --set conjur_app_service_account="poc-conjur-service-account" \
     --set conjur_k8_secret_id_1="data/vault/safe/account/username" \
     --set conjur_k8_secret_id_2="data/vault/safe/account/password" \
     --set conjur_push_secret_name_1="username" \
     --set conjur_push_secret_id_1="data/vault/safe/account/username" \
     --set conjur_push_secret_name_2="password" \
     --set conjur_push_secret_id_2="data/vault/safe/account/password" \
     --set conjur_push_secret_name_3="address" \
     --set conjur_push_secret_id_3="data/vault/safe/account/address" \
     --debug

# ESO CRD
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml

