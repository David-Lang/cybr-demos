#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cloud_dir="$(dirname "$SCRIPT_DIR")"
demo_path="$(dirname "$(dirname "$cloud_dir")")"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(dirname "$(dirname "$(dirname "$demo_path")")")}"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [Azure] $*"; }

set -a
if [[ -f /etc/profile.d/cyberark.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"
# shellcheck disable=SC1091
source "$demo_path/setup/swa/swa_registered.env"
# shellcheck disable=SC1091
source "$cloud_dir/vars.env"
set +a

required_vars=(AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_REGION SWA_OIDC_ISSUER SWA_WORKLOAD_SPIFFE_ID USECASE_ID)
for v in "${required_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "[ERROR] $v is not set" >&2; exit 1; }
done

for cmd in az jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[ERROR] required command not found: $cmd" >&2; exit 1; }
done

SPIFFE_SERVER_HOST="${SWA_OIDC_ISSUER#https://}"

RG_NAME="${USECASE_ID}-spiffe-rg"
IDENTITY_NAME="${USECASE_ID}-spiffe-id"
FEDCRED_NAME="${USECASE_ID}-spiffe-fedcred"

# Azure storage account: max 24 chars, lowercase letters and numbers only
STORAGE_ACCOUNT="$(echo "${USECASE_ID}" | tr -cd 'a-z0-9' | cut -c1-20)spsa"
CONTAINER_NAME="spiffe-demo"
OUT_ENV="$SCRIPT_DIR/azure_registered.env"

log "SPIFFE server: $SPIFFE_SERVER_HOST"
log "SPIFFE ID:     $SWA_WORKLOAD_SPIFFE_ID"
log "Resource group: $RG_NAME"
log "Identity:      $IDENTITY_NAME"
log "Storage:       $STORAGE_ACCOUNT"
log "Region:        $AZURE_REGION"

# Login with service principal credentials injected by Summon, or verify existing login
if [[ -n "${AZURE_CLIENT_SECRET:-}" ]]; then
  log "Logging in with service principal (credentials from CyberArk safe)"
  az login \
    --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --password "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" \
    --output none
elif ! az account show >/dev/null 2>&1; then
  echo "[ERROR] not logged in to Azure and no credentials injected — set AZURE_CLIENT_SECRET or run 'az login'" >&2
  exit 1
fi

az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# ── Resource group ────────────────────────────────────────────────────────────
if az group show --name "$RG_NAME" >/dev/null 2>&1; then
  log "Resource group already exists: $RG_NAME"
else
  log "Creating resource group $RG_NAME"
  az group create --name "$RG_NAME" --location "$AZURE_REGION" --output none
fi

# ── User-assigned managed identity ───────────────────────────────────────────
if az identity show --name "$IDENTITY_NAME" --resource-group "$RG_NAME" >/dev/null 2>&1; then
  log "Managed identity already exists: $IDENTITY_NAME"
else
  log "Creating managed identity $IDENTITY_NAME"
  az identity create \
    --name "$IDENTITY_NAME" \
    --resource-group "$RG_NAME" \
    --location "$AZURE_REGION" \
    --output none
fi

CLIENT_ID="$(az identity show --name "$IDENTITY_NAME" --resource-group "$RG_NAME" --query clientId -o tsv)"
IDENTITY_PRINCIPAL_ID="$(az identity show --name "$IDENTITY_NAME" --resource-group "$RG_NAME" --query principalId -o tsv)"
log "Identity client ID: $CLIENT_ID"

# ── Federated identity credential ─────────────────────────────────────────────
if az identity federated-credential show \
    --name "$FEDCRED_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$RG_NAME" >/dev/null 2>&1; then
  log "Federated credential already exists: $FEDCRED_NAME"
else
  log "Creating federated credential $FEDCRED_NAME"
  az identity federated-credential create \
    --name "$FEDCRED_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$RG_NAME" \
    --issuer "https://${SPIFFE_SERVER_HOST}" \
    --subject "$SWA_WORKLOAD_SPIFFE_ID" \
    --audiences "api://AzureADTokenExchange" \
    --output none
fi

# ── Storage account ───────────────────────────────────────────────────────────
if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RG_NAME" >/dev/null 2>&1; then
  log "Storage account already exists: $STORAGE_ACCOUNT"
else
  log "Creating storage account $STORAGE_ACCOUNT"
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RG_NAME" \
    --location "$AZURE_REGION" \
    --sku Standard_LRS \
    --allow-blob-public-access false \
    --output none
fi

STORAGE_ACCOUNT_KEY="$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RG_NAME" \
  --query '[0].value' -o tsv)"

# ── Blob container ────────────────────────────────────────────────────────────
if az storage container show \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_ACCOUNT_KEY" >/dev/null 2>&1; then
  log "Container already exists: $CONTAINER_NAME"
else
  log "Creating container $CONTAINER_NAME"
  az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_ACCOUNT_KEY" \
    --output none
fi

# ── RBAC: Storage Blob Data Reader on the container ──────────────────────────
STORAGE_SCOPE="$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RG_NAME" \
  --query id -o tsv)/blobServices/default/containers/${CONTAINER_NAME}"

log "Assigning Storage Blob Data Reader to identity"
az role assignment create \
  --assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope "$STORAGE_SCOPE" \
  --output none 2>/dev/null || log "Role assignment already exists (skipping)"

# The setup principal needs data-plane access only for creating/updating test.txt.
if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
  SETUP_SP_OBJECT_ID="$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$SETUP_SP_OBJECT_ID" ]]; then
    log "Assigning Storage Blob Data Contributor to setup service principal"
    az role assignment create \
      --assignee-object-id "$SETUP_SP_OBJECT_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "$STORAGE_SCOPE" \
      --output none 2>/dev/null || log "Setup role assignment already exists (skipping)"
  else
    log "Could not resolve setup service principal object ID — assuming current login already has blob data access"
  fi
fi

# ── Upload test blob ──────────────────────────────────────────────────────────
log "Uploading test blob to ${STORAGE_ACCOUNT}/${CONTAINER_NAME}/test.txt"
echo "hello from cyberark spiffe - azure" \
  | az storage blob upload \
      --account-name "$STORAGE_ACCOUNT" \
      --container-name "$CONTAINER_NAME" \
      --name "test.txt" \
      --data "@-" \
      --overwrite \
      --account-key "$STORAGE_ACCOUNT_KEY" \
      --output none

# ── Write outputs ─────────────────────────────────────────────────────────────
cat > "$OUT_ENV" <<EOF
# Azure cloud registration outputs — do not edit manually
export AZURE_SPIFFE_CLIENT_ID="${CLIENT_ID}"
export AZURE_SPIFFE_TENANT_ID="${AZURE_TENANT_ID}"
export AZURE_SPIFFE_STORAGE_ACCOUNT="${STORAGE_ACCOUNT}"
export AZURE_SPIFFE_CONTAINER="${CONTAINER_NAME}"
export AZURE_SPIFFE_RG="${RG_NAME}"
EOF

log "Wrote $OUT_ENV"

# ── Update K8s ConfigMap for giftapp-swa ──────────────────────────────────────
if command -v kubectl >/dev/null 2>&1; then
  log "Creating/updating giftapp-cloud-spiffe ConfigMap in namespace $NAMESPACE_SWA"
  if ! kubectl get configmap giftapp-cloud-spiffe -n "$NAMESPACE_SWA" >/dev/null 2>&1; then
    kubectl create configmap giftapp-cloud-spiffe --namespace="$NAMESPACE_SWA"
  fi
  kubectl patch configmap giftapp-cloud-spiffe \
    --namespace="$NAMESPACE_SWA" \
    --type merge \
    --patch "{
      \"data\": {
        \"AZURE_SPIFFE_CLIENT_ID\": \"${CLIENT_ID}\",
        \"AZURE_SPIFFE_TENANT_ID\": \"${AZURE_TENANT_ID}\",
        \"AZURE_SPIFFE_STORAGE_ACCOUNT\": \"${STORAGE_ACCOUNT}\",
        \"AZURE_SPIFFE_CONTAINER\": \"${CONTAINER_NAME}\"
      }
    }"

  log "Restarting giftapp-swa deployment"
  kubectl rollout restart deployment/giftapp-swa -n "$NAMESPACE_SWA" || true
else
  log "kubectl not found — skipping ConfigMap creation"
fi

log "Done — client ID: $CLIENT_ID"
