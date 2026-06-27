#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cloud_dir="$(dirname "$SCRIPT_DIR")"
demo_path="$(dirname "$(dirname "$cloud_dir")")"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(dirname "$(dirname "$(dirname "$demo_path")")")}"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [AWS] $*"; }

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

required_vars=(AWS_ACCOUNT_ID AWS_REGION SWA_OIDC_ISSUER SWA_WORKLOAD_SPIFFE_ID USECASE_ID)
for v in "${required_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "[ERROR] $v is not set" >&2; exit 1; }
done

for cmd in aws openssl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[ERROR] required command not found: $cmd" >&2; exit 1; }
done

SPIFFE_SERVER_HOST="${SWA_OIDC_ISSUER#https://}"
SPIFFE_SERVER_HOSTNAME="${SPIFFE_SERVER_HOST%%/*}"
ROLE_NAME="${USECASE_ID}-spiffe-role"
POLICY_NAME="${USECASE_ID}-spiffe-s3-policy"
BUCKET_NAME="${USECASE_ID}-spiffe-demo"
OIDC_PROVIDER_URL="https://${SPIFFE_SERVER_HOST}"
OUT_ENV="$SCRIPT_DIR/aws_registered.env"

log "SPIFFE server: $SPIFFE_SERVER_HOST"
log "SPIFFE hostname: $SPIFFE_SERVER_HOSTNAME"
log "SPIFFE ID:     $SWA_WORKLOAD_SPIFFE_ID"
log "Role:          $ROLE_NAME"
log "Bucket:        $BUCKET_NAME"
log "Region:        $AWS_REGION"

# Derive TLS thumbprint (SHA-1 of the server's leaf cert, no colons)
log "Deriving TLS thumbprint from $SPIFFE_SERVER_HOSTNAME"
TLS_THUMBPRINT=$(openssl s_client -connect "${SPIFFE_SERVER_HOSTNAME}:443" < /dev/null 2>/dev/null \
  | openssl x509 -fingerprint -noout -sha1 \
  | sed 's/.*Fingerprint=//' \
  | tr -d ':')
log "Thumbprint: $TLS_THUMBPRINT"

# ── IAM OIDC provider ────────────────────────────────────────────────────────
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${SPIFFE_SERVER_HOST}"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  log "IAM OIDC provider already exists: $OIDC_ARN"
else
  log "Creating IAM OIDC provider"
  aws iam create-open-id-connect-provider \
    --url "$OIDC_PROVIDER_URL" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "$TLS_THUMBPRINT" \
    --region "$AWS_REGION" \
    --query 'OpenIDConnectProviderArn' --output text
fi

# ── IAM policy ───────────────────────────────────────────────────────────────
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  log "IAM policy already exists: $POLICY_ARN"
else
  log "Creating IAM policy $POLICY_NAME"
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Effect\": \"Allow\",
        \"Action\": [\"s3:GetObject\", \"s3:ListBucket\"],
        \"Resource\": [
          \"arn:aws:s3:::${BUCKET_NAME}\",
          \"arn:aws:s3:::${BUCKET_NAME}/*\"
        ]
      }]
    }" \
    --query 'Policy.Arn' --output text
fi

# ── IAM role with OIDC trust policy ─────────────────────────────────────────
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  log "IAM role already exists: $ROLE_NAME"
else
  log "Creating IAM role $ROLE_NAME"
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Effect\": \"Allow\",
        \"Principal\": {\"Federated\": \"${OIDC_ARN}\"},
        \"Action\": \"sts:AssumeRoleWithWebIdentity\",
        \"Condition\": {\"StringEquals\": {
          \"${SPIFFE_SERVER_HOST}:aud\": \"sts.amazonaws.com\",
          \"${SPIFFE_SERVER_HOST}:sub\": \"${SWA_WORKLOAD_SPIFFE_ID}\"
        }}
      }]
    }" \
    --query 'Role.Arn' --output text
fi

log "Attaching policy to role"
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN"

# ── S3 bucket ────────────────────────────────────────────────────────────────
if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  log "S3 bucket already exists: $BUCKET_NAME"
else
  log "Creating S3 bucket $BUCKET_NAME in $AWS_REGION"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION"
  fi
  aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

log "Uploading test object to s3://${BUCKET_NAME}/test.txt"
echo "hello from cyberark spiffe - aws" \
  | aws s3 cp - "s3://${BUCKET_NAME}/test.txt"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

# ── Write outputs ─────────────────────────────────────────────────────────────
cat > "$OUT_ENV" <<EOF
# AWS cloud registration outputs — do not edit manually
export AWS_SPIFFE_ROLE_ARN="${ROLE_ARN}"
export AWS_SPIFFE_BUCKET="${BUCKET_NAME}"
export AWS_SPIFFE_REGION="${AWS_REGION}"
export AWS_SPIFFE_OIDC_ARN="${OIDC_ARN}"
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
        \"AWS_SPIFFE_ROLE_ARN\": \"${ROLE_ARN}\",
        \"AWS_SPIFFE_BUCKET\": \"${BUCKET_NAME}\",
        \"AWS_SPIFFE_REGION\": \"${AWS_REGION}\"
      }
    }"

  log "Restarting giftapp-swa deployment"
  kubectl rollout restart deployment/giftapp-swa -n "$NAMESPACE_SWA" || true
else
  log "kubectl not found — skipping ConfigMap creation"
fi

log "Done — role ARN: $ROLE_ARN"
