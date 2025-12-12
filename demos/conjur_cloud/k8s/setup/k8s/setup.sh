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
sm_service_name="$SM_SERVICE_NAME"

sm_secret_1_id="$SM_SECRET_1_ID"
sm_secret_1_name="$SM_SECRET_1_NAME"
sm_secret_2_id="$SM_SECRET_2_ID"
sm_secret_2_name="$SM_SECRET_2_NAME"

# Setup k8s

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

openssl s_client -connect "$sm_fqdn":443 </dev/null 2>/dev/null \
| openssl x509 -inform pem -text > sm.pem

# Helm install Release names does not allow '_' use '-'
helm install poc-sm-k8s \
     charts/poc-sm \
     --namespace default \
     --set namespace=$sm_service_name \
     --set sm_fqdn="$sm_fqdn" \
     --set sm_cert_b64="$(cat sm.pem | base64 -w0 )" \
     --set sm_authn_id=$sm_service_name \
     --set sm_app_service_account="poc-service-account" \
     --set sm_secret_1_id="$sm_secret_1_id" \
     --set sm_secret_1_name="$sm_secret_1_name" \
     --set sm_secret_2_id="$sm_secret_2_id" \
     --set sm_secret_2_name="$sm_secret_2_name" \
     --debug
