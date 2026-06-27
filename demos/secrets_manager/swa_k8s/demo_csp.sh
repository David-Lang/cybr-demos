#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

INTERACTIVE=false
RUN_AWS=false
RUN_AZURE=false
EXPLICIT_CLOUD=false

usage() {
  cat <<'EOF'
Usage: ./demo_csp.sh [--aws] [--azure] [--interactive]

Cloud federation demo: zero static cloud credentials using SPIFFE JWT-SVIDs.
Requires the base demo and at least one cloud setup to already be deployed.

Options:
  --aws               Run AWS section (S3 via STS AssumeRoleWithWebIdentity)
  --azure             Run Azure section (Blob Storage via Entra federation)
  -i, --interactive   Pause before each step.
  -h, --help          Show this help.

If neither --aws nor --azure is given, all configured clouds are auto-detected.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aws)   RUN_AWS=true;   EXPLICIT_CLOUD=true ;;
    --azure) RUN_AZURE=true; EXPLICIT_CLOUD=true ;;
    -i|--interactive) INTERACTIVE=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[FAIL] unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

# ── Load environment ──────────────────────────────────────────────────────────

if [[ -f /etc/profile.d/cyberark.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi
if [[ -f "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" ]]; then
  # shellcheck disable=SC1091
  source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
fi

for f in "$SCRIPT_DIR/setup/vars.env" \
         "$SCRIPT_DIR/setup/swa/swa_registered.env" \
         "$SCRIPT_DIR/setup/cloud/vars.env"; do
  if [[ ! -f "$f" ]]; then
    echo "[FAIL] missing required file: $f" >&2
    echo "[FAIL] Run 'bash setup.sh' before running this demo." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a; source "$f"; set +a
done

: "${LAB_ID:?LAB_ID is not set}"
: "${SWA_OIDC_ISSUER:?SWA_OIDC_ISSUER is not set}"

NS_SWA="${NAMESPACE_SWA:-$LAB_ID-giftapp-swa}"
OIDC_HOST="${SWA_OIDC_ISSUER#https://}"

# Auto-detect clouds when no explicit flag given
if [[ "$EXPLICIT_CLOUD" == "false" ]]; then
  [[ -f "$SCRIPT_DIR/setup/cloud/aws/aws_registered.env" ]]     && RUN_AWS=true
  [[ -f "$SCRIPT_DIR/setup/cloud/azure/azure_registered.env" ]] && RUN_AZURE=true
  if [[ "$RUN_AWS" == "false" && "$RUN_AZURE" == "false" ]]; then
    echo "[FAIL] No cloud setup found." >&2
    echo "[FAIL] Run 'bash setup.sh --aws' and/or 'bash setup.sh --azure' first." >&2
    exit 1
  fi
fi

# AWS env
if [[ "$RUN_AWS" == "true" ]]; then
  for f in "$SCRIPT_DIR/setup/cloud/aws/aws_registered.env" \
           "$SCRIPT_DIR/setup/cloud/aws_credentials.env"; do
    if [[ ! -f "$f" ]]; then
      echo "[FAIL] --aws specified but missing: $f" >&2
      echo "[FAIL] Run 'bash setup.sh --aws' first." >&2
      exit 1
    fi
    set -a; source "$f"; set +a
  done
  export AWS_DEFAULT_REGION="$AWS_SPIFFE_REGION"
  : "${AWS_SPIFFE_ROLE_ARN:?AWS_SPIFFE_ROLE_ARN is not set}"
  : "${AWS_SPIFFE_BUCKET:?AWS_SPIFFE_BUCKET is not set}"
  ROLE_NAME="${AWS_SPIFFE_ROLE_ARN##*/}"
fi

# Azure env
if [[ "$RUN_AZURE" == "true" ]]; then
  for f in "$SCRIPT_DIR/setup/cloud/azure/azure_registered.env" \
           "$SCRIPT_DIR/setup/cloud/azure_credentials.env"; do
    if [[ ! -f "$f" ]]; then
      echo "[FAIL] --azure specified but missing: $f" >&2
      echo "[FAIL] Run 'bash setup.sh --azure' first." >&2
      exit 1
    fi
    set -a; source "$f"; set +a
  done
  : "${AZURE_SPIFFE_CLIENT_ID:?AZURE_SPIFFE_CLIENT_ID is not set}"
  : "${AZURE_SPIFFE_STORAGE_ACCOUNT:?AZURE_SPIFFE_STORAGE_ACCOUNT is not set}"
  : "${AZURE_SPIFFE_CONTAINER:?AZURE_SPIFFE_CONTAINER is not set}"
  : "${AZURE_SPIFFE_TENANT_ID:?AZURE_SPIFFE_TENANT_ID is not set}"
  : "${AZURE_SPIFFE_RG:?AZURE_SPIFFE_RG is not set}"
  AZURE_SPIFFE_IDENTITY_NAME="${USECASE_ID}-spiffe-id"
  AZURE_SPIFFE_FEDCRED_NAME="${USECASE_ID}-spiffe-fedcred"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] required tool not found: $1" >&2; exit 1; }
}

pause() {
  [[ "$INTERACTIVE" == "true" ]] && read -r -p "Press Enter to continue..."
}

section() { printf "\n=== %s ===\n" "$1"; }

run_cmd() {
  section "$1"
  printf "Command: %s\n\n" "$2"
  bash -c "$2"
  pause
}

show_instruction() {
  section "$1"
  printf "%s\n" "$2"
  pause
}

run_func() {
  section "$1"
  printf "Command: %s\n\n" "$2"
  "$3"
  pause
}

STEP=0
S() { STEP=$((STEP+1)); printf '%s' "$STEP"; }

# ── Functions ─────────────────────────────────────────────────────────────────

_fetch_jwt_svid_in_pod() {
  local audience="$1"
  local pod
  pod="$(kubectl get pods -n "$NS_SWA" -l app=giftapp-swa \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"

  kubectl exec -i -n "$NS_SWA" "pod/$pod" -- sh <<POD_SCRIPT
set -euo pipefail
grpcurl_version="\${GRPCURL_VERSION:-1.9.3}"
cd /tmp
if [ ! -x /tmp/grpcurl ]; then
  wget -qO- "https://github.com/fullstorydev/grpcurl/releases/download/v\${grpcurl_version}/grpcurl_\${grpcurl_version}_linux_x86_64.tar.gz" \
    | tar -xz grpcurl
  chmod +x /tmp/grpcurl
fi
cat > /tmp/workloadapi.proto <<'EOF_PROTO'
syntax = "proto3";
service SpiffeWorkloadAPI {
  rpc FetchJWTSVID(JWTSVIDRequest) returns (JWTSVIDResponse);
}
message JWTSVIDRequest { repeated string audience = 1; string spiffe_id = 2; }
message JWTSVIDResponse { repeated JWTSVID svids = 1; }
message JWTSVID { string spiffe_id = 1; string svid = 2; string hint = 3; }
EOF_PROTO
/tmp/grpcurl \
  -plaintext \
  -H 'workload.spiffe.io: true' \
  -import-path /tmp -proto workloadapi.proto \
  -d "{\"audience\":[\"$audience\"]}" \
  unix:///tmp/swa-agent/public/api.sock \
  SpiffeWorkloadAPI/FetchJWTSVID
POD_SCRIPT
}

_decode_and_print_jwt() {
  local raw_jwt="$1"
  local jwt
  jwt="$(printf '%s' "$raw_jwt" | jq -r '.svids[0].svid')"
  printf '\nRaw JWT-SVID (truncated):\n%s...\n\n' "${jwt:0:80}"
  printf 'Decoded claims:\n'
  printf '%s' "$jwt" | cut -d'.' -f2 \
    | awk '{ pad=4-length($0)%4; if(pad<4) for(i=0;i<pad;i++) $0=$0"="; print }' \
    | base64 -d 2>/dev/null \
    | jq '{ iss, sub, aud, iat: (.iat | todate), exp: (.exp | todate) }'
}

# ── AWS functions ─────────────────────────────────────────────────────────────

fetch_spiffe_jwt_for_aws() {
  _decode_and_print_jwt "$(_fetch_jwt_svid_in_pod "sts.amazonaws.com")"
}

show_trust_policy() {
  printf 'IAM OIDC Provider:\n'
  aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$AWS_SPIFFE_OIDC_ARN" \
    | jq '{ Url, ClientIDList, ThumbprintList }'

  printf '\nIAM Role Trust Policy:\n'
  aws iam get-role --role-name "$ROLE_NAME" \
    | jq '.Role.AssumeRolePolicyDocument.Statement[0] | {
        Effect, Principal, Action, Condition
      }'
}

csp_test_aws() {
  kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
    wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=aws" | jq .
}

edit_and_refetch_aws() {
  local key_id secret
  key_id="$(grep AWS_ACCESS_KEY_ID "$SCRIPT_DIR/setup/cloud/aws_credentials.env" | cut -d'"' -f2)"
  secret="$(grep AWS_SECRET_ACCESS_KEY "$SCRIPT_DIR/setup/cloud/aws_credentials.env" | cut -d'"' -f2)"

  printf 'Updating s3://%s/test.txt ...\n' "$AWS_SPIFFE_BUCKET"
  echo "hello from cyberark spiffe - aws - updated by demo - $(date -u +%H:%M:%SZ)" \
    | AWS_ACCESS_KEY_ID="$key_id" AWS_SECRET_ACCESS_KEY="$secret" \
      AWS_DEFAULT_REGION="$AWS_SPIFFE_REGION" \
      aws s3 cp - "s3://$AWS_SPIFFE_BUCKET/test.txt"

  printf '\nFetching again via SPIFFE:\n'
  kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
    wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=aws" | jq .
}

# ── Azure functions ───────────────────────────────────────────────────────────

fetch_spiffe_jwt_for_azure() {
  _decode_and_print_jwt "$(_fetch_jwt_svid_in_pod "api://AzureADTokenExchange")"
}

show_federated_credential() {
  printf 'Managed Identity:\n'
  az identity show \
    --name "$AZURE_SPIFFE_IDENTITY_NAME" \
    --resource-group "$AZURE_SPIFFE_RG" \
    | jq '{ name, clientId, principalId, location }'

  printf '\nFederated Identity Credential:\n'
  az identity federated-credential show \
    --name "$AZURE_SPIFFE_FEDCRED_NAME" \
    --identity-name "$AZURE_SPIFFE_IDENTITY_NAME" \
    --resource-group "$AZURE_SPIFFE_RG" \
    | jq '{ name, issuer, subject, audiences }'
}

csp_test_azure() {
  kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
    wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=azure" | jq .
}

edit_and_refetch_azure() {
  local client_id client_secret setup_sp_object_id storage_scope
  client_id="$(grep -v '^#' "$SCRIPT_DIR/setup/cloud/azure_credentials.env" \
    | grep AZURE_CLIENT_ID | cut -d'"' -f2)"
  client_secret="$(grep -v '^#' "$SCRIPT_DIR/setup/cloud/azure_credentials.env" \
    | grep AZURE_CLIENT_SECRET | cut -d'"' -f2)"

  printf 'Logging in to Azure as service principal...\n'
  az login --service-principal \
    --username "$client_id" \
    --password "$client_secret" \
    --tenant "$AZURE_SPIFFE_TENANT_ID" \
    --output none

  setup_sp_object_id="$(az ad sp show --id "$client_id" --query id -o tsv 2>/dev/null || true)"
  storage_scope="$(az storage account show \
    --name "$AZURE_SPIFFE_STORAGE_ACCOUNT" \
    --resource-group "$AZURE_SPIFFE_RG" \
    --query id -o tsv)/blobServices/default/containers/${AZURE_SPIFFE_CONTAINER}"
  if [[ -n "$setup_sp_object_id" ]]; then
    az role assignment create \
      --assignee-object-id "$setup_sp_object_id" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "$storage_scope" \
      --output none 2>/dev/null || true
  fi

  printf 'Updating %s/%s/test.txt ...\n' \
    "$AZURE_SPIFFE_STORAGE_ACCOUNT" "$AZURE_SPIFFE_CONTAINER"
  echo "hello from cyberark spiffe - azure - updated by demo - $(date -u +%H:%M:%SZ)" \
    | az storage blob upload \
        --account-name "$AZURE_SPIFFE_STORAGE_ACCOUNT" \
        --container-name "$AZURE_SPIFFE_CONTAINER" \
        --name "test.txt" \
        --data "@-" \
        --overwrite \
        --auth-mode login \
        --output none

  printf '\nFetching again via SPIFFE:\n'
  kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
    wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=azure" | jq .
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

require_tool kubectl
require_tool jq
[[ "$RUN_AWS" == "true" ]]   && require_tool aws
[[ "$RUN_AZURE" == "true" ]] && require_tool az

kubectl get pods -n "$NS_SWA" -l app=giftapp-swa \
  --field-selector=status.phase=Running -o name | grep -q . \
  || { echo "[FAIL] no Running giftapp-swa pod in $NS_SWA" >&2; exit 1; }

# ── Intro ─────────────────────────────────────────────────────────────────────

CLOUDS_CONFIGURED=""
[[ "$RUN_AWS" == "true" ]]   && CLOUDS_CONFIGURED+=" AWS"
[[ "$RUN_AZURE" == "true" ]] && CLOUDS_CONFIGURED+=" Azure"

cat <<EOF

Cloud Federation Demo — Zero Static Credentials with SPIFFE

Lab:        $LAB_ID
Namespace:  $NS_SWA
Clouds:    ${CLOUDS_CONFIGURED}
OIDC Host:  $OIDC_HOST

Interactive: $INTERACTIVE
EOF

pause

# ── AWS ───────────────────────────────────────────────────────────────────────

if [[ "$RUN_AWS" == "true" ]]; then

show_instruction "$(S). The Problem — Static AWS Credentials" \
  "Traditional apps access AWS by storing long-lived credentials somewhere:
    - Kubernetes Secrets (base64 in etcd)
    - Environment variables in the pod spec
    - Mounted config files

  Any of these can be stolen with: kubectl exec, kubectl get secret,
  a compromised CI pipeline, or access to the etcd backup.

  Once stolen, the credentials work until manually rotated.
  There is no record of which workload used them or when.

  This demo shows a different model: the workload has no AWS credentials at all.
  Its cryptographic SPIFFE identity IS the credential."

show_instruction "$(S). What the Workload Has Instead — A SPIFFE Identity" \
  "The SWA Agent runs as a DaemonSet on every node and exposes a Unix socket
  inside every pod at /tmp/swa-agent/public/api.sock.

  Any workload can call this socket to receive a signed JWT-SVID.
  The JWT is:
    - Issued and signed by the SWA Server (acts as an OIDC provider)
    - Scoped to a specific audience (e.g. sts.amazonaws.com)
    - Short-lived (expires in minutes)
    - Bound to this exact workload's SPIFFE ID

  No secret material is stored anywhere. The identity is proven cryptographically
  at runtime, not by presenting a password."

run_func "$(S). Fetch a Live JWT-SVID (audience: sts.amazonaws.com)" \
  "grpcurl -d '{\"audience\":[\"sts.amazonaws.com\"]}' unix:///tmp/swa-agent/public/api.sock SpiffeWorkloadAPI/FetchJWTSVID | decode claims" \
  fetch_spiffe_jwt_for_aws

show_instruction "$(S). How AWS Trusts This Identity — The OIDC Trust Chain" \
  "AWS IAM is configured to trust JWTs issued by the SWA Server via OIDC federation:

    SWA Server
      └─ publishes OIDC discovery at: $SWA_OIDC_ISSUER
           └─ IAM OIDC Provider registered in AWS account $AWS_ACCOUNT_ID
                └─ IAM Role trust policy pins to the exact SPIFFE ID:
                     Condition:
                       StringEquals:
                         ${OIDC_HOST}:aud: sts.amazonaws.com
                         ${OIDC_HOST}:sub: $SWA_WORKLOAD_SPIFFE_ID

  No other workload — even in the same cluster — can assume this role.
  The trust is pinned to the cryptographic identity of giftapp-swa specifically."

run_func "$(S). Show IAM OIDC Provider and Role Trust Policy" \
  "aws iam get-open-id-connect-provider && aws iam get-role --role-name $ROLE_NAME" \
  show_trust_policy

show_instruction "$(S). The Full AWS Flow at Runtime" \
  "When giftapp-swa calls /csp-test?cloud=aws:

    1. Fetch JWT-SVID from SWA Agent socket  (audience: sts.amazonaws.com)
    2. POST to AWS STS AssumeRoleWithWebIdentity with the JWT
    3. STS validates JWT signature against the OIDC discovery endpoint
    4. STS checks aud and sub claims match the role trust policy
    5. STS returns temporary credentials (valid ~1 hour, never stored)
    6. Sign S3 GetObject request with SigV4 using those credentials
    7. Return the file contents

  Zero static credentials. Every access is freshly authenticated."

run_func "$(S). Call the Endpoint — Full SPIFFE → STS → S3 Flow" \
  "curl -sk https://localhost:8443/csp-test?cloud=aws | jq ." \
  csp_test_aws

show_instruction "$(S). Prove the Fetch Is Live — Edit the S3 File" \
  "We'll update test.txt directly in S3, then call the endpoint again.
  The response will immediately reflect the new content — proving the app
  fetches from S3 on every call with freshly-issued STS credentials.

  No cache. No stored token. Each call re-authenticates."

run_func "$(S). Update S3 File and Re-Fetch" \
  "echo 'hello from cyberark spiffe - aws - updated by demo' | aws s3 cp - s3://$AWS_SPIFFE_BUCKET/test.txt && curl /csp-test?cloud=aws" \
  edit_and_refetch_aws

fi  # RUN_AWS

# ── Azure ─────────────────────────────────────────────────────────────────────

if [[ "$RUN_AZURE" == "true" ]]; then

show_instruction "$(S). The Problem — Static Azure Credentials" \
  "Traditional apps access Azure by storing long-lived credentials somewhere:
    - Kubernetes Secrets holding AZURE_CLIENT_ID and AZURE_CLIENT_SECRET
    - Environment variables in the pod spec
    - Mounted service principal credential files

  Any of these can be stolen with: kubectl exec, kubectl get secret,
  a compromised CI pipeline, or access to the etcd backup.

  Once stolen, the service principal credentials work until manually rotated.
  Azure audit logs record the app ID — not which workload used it.

  This demo shows a different model: the workload has no Azure credentials at all.
  Its cryptographic SPIFFE identity IS the credential."

show_instruction "$(S). What the Workload Has Instead — A SPIFFE Identity" \
  "The SWA Agent exposes the same Unix socket used for AWS, but the audience
  changes per cloud provider.

  For Azure, the workload requests a JWT-SVID with:
    audience: api://AzureADTokenExchange

  This is the audience Entra ID expects for workload identity federation.
  The JWT is short-lived, signed by the SWA Server, and bound to this
  exact workload's SPIFFE ID — no service principal secret involved."

run_func "$(S). Fetch a Live JWT-SVID (audience: api://AzureADTokenExchange)" \
  "grpcurl -d '{\"audience\":[\"api://AzureADTokenExchange\"]}' unix:///tmp/swa-agent/public/api.sock SpiffeWorkloadAPI/FetchJWTSVID | decode claims" \
  fetch_spiffe_jwt_for_azure

show_instruction "$(S). How Azure Trusts This Identity — Entra Federated Identity Credential" \
  "Azure uses a Federated Identity Credential on a Managed Identity as the trust anchor:

    SWA Server
      └─ publishes OIDC discovery at: $SWA_OIDC_ISSUER
           └─ Managed Identity: $AZURE_SPIFFE_IDENTITY_NAME
                └─ Federated Identity Credential pins:
                     Issuer:   $SWA_OIDC_ISSUER
                     Subject:  $SWA_WORKLOAD_SPIFFE_ID
                     Audience: api://AzureADTokenExchange

  When the workload presents this JWT, Entra ID:
    1. Fetches JWKS from the SWA Server OIDC discovery endpoint
    2. Validates the JWT signature
    3. Checks issuer, subject, and audience match the federated credential
    4. Issues an Entra access token scoped to Azure Storage

  Unlike AWS (one hop: SPIFFE → STS → S3), Azure requires two hops:
    SPIFFE JWT → Entra token exchange → Blob Storage
  The extra hop is how Azure's workload identity federation works."

run_func "$(S). Show Managed Identity and Federated Credential" \
  "az identity show && az identity federated-credential show" \
  show_federated_credential

show_instruction "$(S). The Full Azure Flow at Runtime" \
  "When giftapp-swa calls /csp-test?cloud=azure:

    1. Fetch JWT-SVID from SWA Agent socket  (audience: api://AzureADTokenExchange)
    2. POST to Entra ID token endpoint with the JWT as client_assertion
    3. Entra validates JWT and issues an access token for storage.azure.com
    4. GET blob with Authorization: Bearer <entra-token>
    5. Azure validates token and returns blob content

  Zero static credentials. Every access gets a fresh Entra token via SPIFFE."

run_func "$(S). Call the Endpoint — Full SPIFFE → Entra → Blob Flow" \
  "curl -sk https://localhost:8443/csp-test?cloud=azure | jq ." \
  csp_test_azure

show_instruction "$(S). Prove the Fetch Is Live — Edit the Blob File" \
  "We'll update test.txt directly in Azure Blob Storage using the admin service
  principal, then call the endpoint again.
  The response will immediately reflect the new content — proving the app
  authenticates freshly through Entra on every call.

  No cache. No stored token. Each call re-authenticates."

run_func "$(S). Update Blob and Re-Fetch" \
  "echo 'hello from cyberark spiffe - azure - updated by demo' | az storage blob upload --overwrite && curl /csp-test?cloud=azure" \
  edit_and_refetch_azure

fi  # RUN_AZURE

# ── Summary ───────────────────────────────────────────────────────────────────

summary_aws=""
summary_azure=""

if [[ "$RUN_AWS" == "true" ]]; then
  summary_aws="
  AWS (SPIFFE → STS AssumeRoleWithWebIdentity → S3)
    - No AWS credentials stored anywhere in the cluster
    - IAM role trust policy pinned to exact SPIFFE ID — not just namespace
    - Short-lived STS tokens expire automatically"
fi

if [[ "$RUN_AZURE" == "true" ]]; then
  summary_azure="
  Azure (SPIFFE → Entra Federated Credential → Blob Storage)
    - No Azure credentials stored anywhere in the cluster
    - Federated Identity Credential pinned to exact SPIFFE ID and issuer
    - Entra access tokens are short-lived and never stored"
fi

show_instruction "$(S). Summary" \
  "What we demonstrated:

  BEFORE (static credentials)
    - Cloud keys stored in Kubernetes Secrets or environment variables
    - Stealable via pod exec, secret read, or etcd backup
    - Manual rotation required

  AFTER (SPIFFE identity federation)
${summary_aws}
${summary_azure}

  The only thing that grants cloud access is the workload's SPIFFE identity,
  issued by the SWA Server and verified by each cloud provider via OIDC federation."
