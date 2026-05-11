#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cloud_dir="$(dirname "$SCRIPT_DIR")"
demo_path="$(dirname "$(dirname "$cloud_dir")")"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(dirname "$(dirname "$(dirname "$demo_path")")")}"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [GCP] $*"; }

set -a
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"
# shellcheck disable=SC1091
source "$demo_path/setup/swa/swa_registered.env"
# shellcheck disable=SC1091
source "$cloud_dir/vars.env"
set +a

required_vars=(GCP_PROJECT_ID GCP_REGION SWA_OIDC_ISSUER SWA_WORKLOAD_SPIFFE_ID USECASE_ID)
for v in "${required_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "[ERROR] $v is not set" >&2; exit 1; }
done

for cmd in gcloud jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[ERROR] required command not found: $cmd" >&2; exit 1; }
done

SPIFFE_SERVER_HOST="${SWA_OIDC_ISSUER#https://}"

# Activate service account if key file injected by Summon, or verify existing auth
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  log "Activating service account from key file injected by Summon"
  gcloud auth activate-service-account \
    --key-file="$GOOGLE_APPLICATION_CREDENTIALS" \
    --project="$GCP_PROJECT_ID"
elif ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | grep -q .; then
  echo "[ERROR] no active gcloud authentication and no key file injected — set GOOGLE_APPLICATION_CREDENTIALS or run 'gcloud auth login'" >&2
  exit 1
fi

# GCP resource names: lowercase, hyphens OK, max 32 chars for pool/provider
# SA names: 6-30 chars
POOL_NAME="${USECASE_ID}-pool"
PROVIDER_NAME="${USECASE_ID}-provider"
SA_NAME="$(echo "${USECASE_ID}-spsa" | cut -c1-30)"
BUCKET_NAME="${USECASE_ID}-spiffe-demo"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
OUT_ENV="$SCRIPT_DIR/gcp_registered.env"

# Derive project number
log "Deriving project number for $GCP_PROJECT_ID"
GCP_PROJECT_NUMBER="$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)')"

POOL_AUDIENCE="//iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"

log "SPIFFE server:   $SPIFFE_SERVER_HOST"
log "SPIFFE ID:       $SWA_WORKLOAD_SPIFFE_ID"
log "Project number:  $GCP_PROJECT_NUMBER"
log "Pool:            $POOL_NAME"
log "Pool audience:   $POOL_AUDIENCE"
log "Service account: $SA_EMAIL"
log "Bucket:          $BUCKET_NAME"

# ── Workload identity pool ─────────────────────────────────────────────────────
if gcloud iam workload-identity-pools describe "$POOL_NAME" \
    --location="global" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  log "Workload identity pool already exists: $POOL_NAME"
else
  log "Creating workload identity pool $POOL_NAME"
  gcloud iam workload-identity-pools create "$POOL_NAME" \
    --location="global" \
    --display-name="CyberArk SPIFFE Demo Pool" \
    --project="$GCP_PROJECT_ID"
fi

# ── OIDC provider ─────────────────────────────────────────────────────────────
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --workload-identity-pool="$POOL_NAME" \
    --location="global" \
    --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  log "OIDC provider already exists: $PROVIDER_NAME"
else
  log "Creating OIDC provider $PROVIDER_NAME"
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
    --location="global" \
    --workload-identity-pool="$POOL_NAME" \
    --issuer-uri="https://${SPIFFE_SERVER_HOST}" \
    --allowed-audiences="$POOL_AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub" \
    --attribute-condition="google.subject == '${SWA_WORKLOAD_SPIFFE_ID}'" \
    --project="$GCP_PROJECT_ID"
fi

# ── Service account ────────────────────────────────────────────────────────────
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  log "Service account already exists: $SA_EMAIL"
else
  log "Creating service account $SA_NAME"
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="CyberArk SPIFFE Demo Service Account" \
    --project="$GCP_PROJECT_ID"
fi

# ── Allow federated identity to impersonate the SA ────────────────────────────
MEMBER="principal://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/subject/${SWA_WORKLOAD_SPIFFE_ID}"
log "Binding workloadIdentityUser to $SA_EMAIL"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$MEMBER" \
  --project="$GCP_PROJECT_ID" \
  --quiet

# ── GCS bucket ────────────────────────────────────────────────────────────────
if gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  log "GCS bucket already exists: $BUCKET_NAME"
else
  log "Creating GCS bucket $BUCKET_NAME in $GCP_REGION"
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --location="$GCP_REGION" \
    --uniform-bucket-level-access \
    --project="$GCP_PROJECT_ID"
fi

# ── Grant SA read access to bucket ────────────────────────────────────────────
log "Granting storage.objectViewer to $SA_EMAIL on $BUCKET_NAME"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectViewer" \
  --quiet

# ── Upload test file ──────────────────────────────────────────────────────────
log "Uploading test file to gs://${BUCKET_NAME}/test.txt"
echo "hello from cyberark spiffe - gcp" \
  | gcloud storage cp - "gs://${BUCKET_NAME}/test.txt" --project="$GCP_PROJECT_ID"

# ── Write outputs ─────────────────────────────────────────────────────────────
cat > "$OUT_ENV" <<EOF
# GCP cloud registration outputs — do not edit manually
export GCP_SPIFFE_PROJECT_ID="${GCP_PROJECT_ID}"
export GCP_SPIFFE_PROJECT_NUMBER="${GCP_PROJECT_NUMBER}"
export GCP_SPIFFE_POOL_AUDIENCE="${POOL_AUDIENCE}"
export GCP_SPIFFE_SA_EMAIL="${SA_EMAIL}"
export GCP_SPIFFE_BUCKET="${BUCKET_NAME}"
export GCP_SPIFFE_REGION="${GCP_REGION}"
EOF

log "Wrote $OUT_ENV"
log "Done — pool audience: $POOL_AUDIENCE"
