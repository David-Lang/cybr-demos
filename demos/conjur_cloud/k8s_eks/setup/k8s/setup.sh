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

# Helm install ESO Service


kubectl get crd externalsecrets.external-secrets.io secretstores.external-secrets.io \
  -o custom-columns=NAME:.metadata.name,VERSIONS:.spec.versions[*].name


helm repo add external-secrets https://charts.external-secrets.io
helm repo update

kubectl create namespace external-secrets 2>/dev/null || true
helm install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --set installCRDs=true \
    --debug

kubectl api-resources | grep -Ei 'externalsecret|secretstore'
kubectl get crd | grep -i external-secrets || echo "no external-secrets CRDs"
kubectl get crd | grep -Ei 'externalsecret|secretstore' || echo "no CRDs for ExternalSecret/SecretStore"
kubectl -n external-secrets get pods

# ESO CRD
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml


# Helm install Release names does not allow '_' use '-'
helm install poc-sm-k8s-eks \
     charts/poc-sm \
     --namespace default \
     --set namespace=$sm_namespace \
     --set sm_fqdn="$sm_fqdn" \
     --set sm_cert_b64="$(cat sm.pem | base64 -w0 )" \
     --set sm_authn_id="k8s-eks-1" \
     --set sm_app_service_account="poc-service-account" \
     --set sm_k8_secret_id_1="data/vault/safe/account/username" \
     --set sm_k8_secret_id_2="data/vault/safe/account/password" \
     --set sm_push_secret_name_1="username" \
     --set sm_push_secret_id_1="data/vault/safe/account/username" \
     --set sm_push_secret_name_2="password" \
     --set sm_push_secret_id_2="data/vault/safe/account/password" \
     --set sm_push_secret_name_3="address" \
     --set sm_push_secret_id_3="data/vault/safe/account/address" \
     --debug

