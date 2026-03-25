#!/usr/bin/env bash
# Get Hashi Cert
resolve_template "cert_request.tmpl.yaml" "cert_request.yaml"
kubectl apply -f cert_request.yaml
sleep 30
kubectl get secret vault-server-tls -n hashi-vault

# Hashi Helm Chart
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Standalone Mode (Persistent)
helm install vault hashicorp/vault -n hashi-vault -f vault_values.yaml

kubectl get pods -n hashi-vault
kubectl get svc -n hashi-vault

vault_init_file="vault_init_output"
kubectl exec vault-0 -n hashi-vault -- env VAULT_ADDR='https://127.0.0.1:8200' vault operator init -tls-skip-verify > $vault_init_file
cat $vault_init_file

# Extract VAULT_ADDR
vault_init_addr=$(grep -oP "VAULT_ADDR='\K[^']+" "$vault_init_file")

# Extract Initial Root Token
export vault_token
vault_token=$(grep "Initial Root Token:" "$vault_init_file" | awk '{print $NF}')

# Extract Unseal Keys
unseal_key_1=$(grep "Unseal Key 1:" "$vault_init_file" | awk '{print $NF}')
unseal_key_2=$(grep "Unseal Key 2:" "$vault_init_file" | awk '{print $NF}')
unseal_key_3=$(grep "Unseal Key 3:" "$vault_init_file" | awk '{print $NF}')

# Capture output
kubectl exec vault-0 -n hashi-vault -- env VAULT_ADDR="$vault_init_addr" vault operator unseal -tls-skip-verify $unseal_key_1
kubectl exec vault-0 -n hashi-vault -- env VAULT_ADDR="$vault_init_addr" vault operator unseal -tls-skip-verify $unseal_key_2
kubectl exec vault-0 -n hashi-vault -- env VAULT_ADDR="$vault_init_addr" vault operator unseal -tls-skip-verify $unseal_key_3

# Inspect
kubectl get pods -n hashi-vault
kubectl logs vault-0 -n hashi-vault
kubectl exec vault-0 -n hashi-vault -- vault status
kubectl -n hashi-vault run nettest --rm -it --image=curlimages/curl -- curl -vk https://"$vault_init_addr"/v1/sys/health

curl -vk --max-time 5 https://$VAULT_ADDR/v1/sys/health

# Configure
install_cli.sh
add_kv2_secrets.sh
create_secrets_hub_access.sh

# Setup auto unseal
resolve_template "unseal_cronjob.tmpl.yaml" "unseal_cronjob.yaml"
kubectl apply -f unseal_cronjob.yaml
