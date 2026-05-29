# Azure SPIFFE JWT-SVID Testing Guide

This guide covers testing the Azure Blob Storage integration using SPIFFE JWT-SVIDs fetched from the SWA Agent.

## Prerequisites

Before spinning up a new lab, you need:

- Azure tenant ID
- Azure subscription ID
- Azure region, for example `eastus`
- Azure service principal credentials with permissions to:
  - Create resource groups
  - Create user-assigned managed identities
  - Create federated identity credentials
  - Create storage accounts and containers
  - Assign RBAC roles at the storage container scope

## Configuration

Edit the shared cloud inputs:

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
vi setup/cloud/vars.env
```

Fill in:

```bash
AZURE_TENANT_ID="00000000-0000-0000-0000-000000000000"
AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
AZURE_REGION="eastus"
```

Create or edit the Azure credentials file:

```bash
vi setup/cloud/azure_credentials.env
```

Fill in:

```bash
AZURE_CLIENT_ID="00000000-0000-0000-0000-000000000000"
AZURE_CLIENT_SECRET="..."
```

## Deployment

Run the full demo setup with Azure enabled:

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
bash setup.sh --azure
```

This creates:

- Resource group: `<usecase-id>-spiffe-rg`
- User-assigned managed identity: `<usecase-id>-spiffe-id`
- Federated identity credential pinned to the SWA issuer, workload SPIFFE ID, and `api://AzureADTokenExchange`
- Storage account and `spiffe-demo` container
- `test.txt` blob
- `Storage Blob Data Reader` assignment for the managed identity
- Kubernetes ConfigMap `giftapp-cloud-spiffe` with Azure runtime config

## Testing

Verify the Azure registration outputs:

```bash
cat setup/cloud/azure/azure_registered.env
```

Expected values:

```bash
export AZURE_SPIFFE_CLIENT_ID="..."
export AZURE_SPIFFE_TENANT_ID="..."
export AZURE_SPIFFE_STORAGE_ACCOUNT="..."
export AZURE_SPIFFE_CONTAINER="spiffe-demo"
export AZURE_SPIFFE_RG="..."
```

Verify the Kubernetes ConfigMap:

```bash
source setup/vars.env
kubectl describe configmap giftapp-cloud-spiffe -n "$NAMESPACE_SWA"
```

Expected keys:

```text
AZURE_SPIFFE_CLIENT_ID
AZURE_SPIFFE_TENANT_ID
AZURE_SPIFFE_STORAGE_ACCOUNT
AZURE_SPIFFE_CONTAINER
```

Verify the pod received the runtime config:

```bash
kubectl exec -n "$NAMESPACE_SWA" deployment/giftapp-swa -- \
  env | grep AZURE_SPIFFE
```

Test the endpoint:

```bash
kubectl exec -n "$NAMESPACE_SWA" deployment/giftapp-swa -- \
  wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=azure"
```

Expected successful response:

```json
{
  "cloud": "azure",
  "spiffeId": "spiffe://<trust-domain>/<node-group>/workload/<namespace>/giftapp-swa-sa",
  "audience": "api://AzureADTokenExchange",
  "source": "https://<storage-account>.blob.core.windows.net/spiffe-demo/test.txt",
  "content": "hello from cyberark spiffe - azure"
}
```

## Demo Script

Run the Azure section of the CSP demo:

```bash
bash demo_csp.sh --azure
```

The script shows:

- No static Azure client secret in the pod
- Live JWT-SVID issuance for `api://AzureADTokenExchange`
- Managed identity federated credential configuration
- Full SPIFFE to Entra token exchange to Blob Storage read
- Optional Entra sign-in log lookup

## Troubleshooting

### Missing Azure Environment Variables

Symptom:

```text
AZURE_SPIFFE_CLIENT_ID, AZURE_SPIFFE_TENANT_ID, AZURE_SPIFFE_STORAGE_ACCOUNT, and AZURE_SPIFFE_CONTAINER must be set
```

Check:

```bash
kubectl get configmap giftapp-cloud-spiffe -n "$NAMESPACE_SWA" -o yaml
kubectl rollout status deployment/giftapp-swa -n "$NAMESPACE_SWA"
```

Fix by re-running:

```bash
cd setup/cloud/azure
set -a
source ../azure_credentials.env
set +a
bash setup.sh
```

### Entra Token Exchange Fails

Check the federated identity credential:

```bash
source setup/cloud/azure/azure_registered.env
az identity federated-credential show \
  --name "<usecase-id>-spiffe-fedcred" \
  --identity-name "<usecase-id>-spiffe-id" \
  --resource-group "$AZURE_SPIFFE_RG"
```

The issuer must match `SWA_OIDC_ISSUER`, the subject must match `SWA_WORKLOAD_SPIFFE_ID`, and the audience must be `api://AzureADTokenExchange`.

### Blob GET Returns 403

Check the managed identity has `Storage Blob Data Reader` on the container:

```bash
az role assignment list \
  --assignee "$AZURE_SPIFFE_CLIENT_ID" \
  --scope "$(az storage account show \
    --name "$AZURE_SPIFFE_STORAGE_ACCOUNT" \
    --resource-group "$AZURE_SPIFFE_RG" \
    --query id -o tsv)/blobServices/default/containers/$AZURE_SPIFFE_CONTAINER" \
  -o table
```

RBAC propagation can take a few minutes. Wait and retry `/csp-test?cloud=azure`.
