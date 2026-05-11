#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

INTERACTIVE=false

usage() {
  cat <<'EOF'
Usage: ./demo_csp.sh [--interactive]

Cloud federation demo: zero static AWS credentials using SPIFFE JWT-SVIDs.
Requires the base demo and AWS cloud setup to already be deployed.

Options:
  -i, --interactive   Pause before each step.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
         "$SCRIPT_DIR/setup/cloud/aws/aws_registered.env" \
         "$SCRIPT_DIR/setup/cloud/aws_credentials.env" \
         "$SCRIPT_DIR/setup/cloud/vars.env"; do
  if [[ ! -f "$f" ]]; then
    echo "[FAIL] missing required file: $f" >&2
    echo "[FAIL] Run 'bash setup.sh --aws' before running this demo." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a; source "$f"; set +a
done

export AWS_DEFAULT_REGION="$AWS_SPIFFE_REGION"

: "${LAB_ID:?LAB_ID is not set}"
: "${AWS_SPIFFE_ROLE_ARN:?AWS_SPIFFE_ROLE_ARN is not set}"
: "${AWS_SPIFFE_BUCKET:?AWS_SPIFFE_BUCKET is not set}"
: "${SWA_OIDC_ISSUER:?SWA_OIDC_ISSUER is not set}"

NS_SWA="${NAMESPACE_SWA:-$LAB_ID-giftapp-swa}"
ROLE_NAME="${AWS_SPIFFE_ROLE_ARN##*/}"
OIDC_HOST="${SWA_OIDC_ISSUER#https://}"

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
  pause
  bash -c "$2"
}

show_instruction() {
  section "$1"
  printf "%s\n" "$2"
  pause
}

run_func() {
  section "$1"
  printf "Command: %s\n\n" "$2"
  pause
  "$3"
}

# ── Functions ─────────────────────────────────────────────────────────────────

fetch_spiffe_jwt_for_aws() {
  local pod
  pod="$(kubectl get pods -n "$NS_SWA" -l app=giftapp-swa \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"

  local raw_jwt
  raw_jwt="$(kubectl exec -i -n "$NS_SWA" "pod/$pod" -- sh <<'POD_SCRIPT'
set -euo pipefail
grpcurl_version="${GRPCURL_VERSION:-1.9.3}"
cd /tmp
if [ ! -x /tmp/grpcurl ]; then
  wget -qO- "https://github.com/fullstorydev/grpcurl/releases/download/v${grpcurl_version}/grpcurl_${grpcurl_version}_linux_x86_64.tar.gz" \
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
  -d '{"audience":["sts.amazonaws.com"]}' \
  unix:///tmp/swa-agent/public/api.sock \
  SpiffeWorkloadAPI/FetchJWTSVID
POD_SCRIPT
)"

  local jwt
  jwt="$(printf '%s' "$raw_jwt" | jq -r '.svids[0].svid')"

  printf '\nRaw JWT-SVID (truncated):\n%s...\n\n' "${jwt:0:80}"
  printf 'Decoded claims:\n'
  printf '%s' "$jwt" | cut -d'.' -f2 \
    | awk '{ pad=4-length($0)%4; if(pad<4) for(i=0;i<pad;i++) $0=$0"="; print }' \
    | base64 -d 2>/dev/null \
    | jq '{
        iss,
        sub,
        aud,
        iat: (.iat | todate),
        exp: (.exp | todate)
      }'
}

show_trust_policy() {
  printf 'IAM OIDC Provider:\n'
  aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$AWS_SPIFFE_OIDC_ARN" \
    | jq '{ Url, ClientIDList, ThumbprintList }'

  printf '\nIAM Role Trust Policy:\n'
  aws iam get-role --role-name "$ROLE_NAME" \
    | jq '.Role.AssumeRolePolicyDocument.Statement[0] | {
        Effect,
        Principal,
        Action,
        Condition
      }'
}

csp_test_aws() {
  kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
    wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=aws" | jq .
}

edit_and_refetch() {
  local key_id secret

  key_id="$(grep AWS_ACCESS_KEY_ID "$SCRIPT_DIR/setup/cloud/aws_credentials.env" | cut -d'"' -f2)"
  secret="$(grep AWS_SECRET_ACCESS_KEY "$SCRIPT_DIR/setup/cloud/aws_credentials.env" | cut -d'"' -f2)"

  printf 'Updating s3://%s/test.txt ...\n' "$AWS_SPIFFE_BUCKET"
  echo "updated by demo - $(date -u +%H:%M:%SZ)" \
    | AWS_ACCESS_KEY_ID="$key_id" AWS_SECRET_ACCESS_KEY="$secret" \
      AWS_DEFAULT_REGION="$AWS_SPIFFE_REGION" \
      aws s3 cp - "s3://$AWS_SPIFFE_BUCKET/test.txt"

  printf '\nFetching again via SPIFFE:\n'
  kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
    wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=aws" | jq .
}

show_cloudtrail() {
  local event
  event="$(aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
    --max-results 5 \
    | jq '[.Events[] | .CloudTrailEvent | fromjson
           | select(.requestParameters.roleArn == "'"$AWS_SPIFFE_ROLE_ARN"'")]
          | first')"

  if [[ -z "$event" || "$event" == "null" ]]; then
    printf 'No AssumeRoleWithWebIdentity events found yet — try calling the endpoint first.\n'
    return
  fi

  printf 'CloudTrail event summary:\n'
  printf '%s' "$event" | jq '{
    eventTime,
    sourceIPAddress,
    roleArn: .requestParameters.roleArn,
    roleSessionName: .requestParameters.roleSessionName,
    webIdentityProvider: .requestParameters.principalTags
  }'

  printf '\nDecoded SPIFFE ID from JWT sub claim:\n'
  local jwt payload
  jwt="$(printf '%s' "$event" | jq -r '.requestParameters.webIdentityToken // empty')"
  if [[ -n "$jwt" ]]; then
    payload="$(printf '%s' "$jwt" | cut -d'.' -f2 \
      | awk '{ pad=4-length($0)%4; if(pad<4) for(i=0;i<pad;i++) $0=$0"="; print }' \
      | base64 -d 2>/dev/null)"
    printf '%s' "$payload" | jq '{ sub, aud, iss, exp: (.exp | todate) }'
  else
    printf '(webIdentityToken not included in CloudTrail event — check CloudTrail data events)\n'
    printf '%s' "$event" | jq '.userIdentity'
  fi
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

require_tool kubectl
require_tool aws
require_tool jq

kubectl get pods -n "$NS_SWA" -l app=giftapp-swa \
  --field-selector=status.phase=Running -o name | grep -q . \
  || { echo "[FAIL] no Running giftapp-swa pod in $NS_SWA" >&2; exit 1; }

# ── Intro ─────────────────────────────────────────────────────────────────────

cat <<EOF

Cloud Federation Demo — Zero Static AWS Credentials with SPIFFE

Lab:        $LAB_ID
Namespace:  $NS_SWA
AWS Role:   $AWS_SPIFFE_ROLE_ARN
S3 Bucket:  $AWS_SPIFFE_BUCKET
OIDC Host:  $OIDC_HOST

Interactive: $INTERACTIVE
EOF

pause

# ── Part 1: The Problem ───────────────────────────────────────────────────────

show_instruction "1. The Problem — Static Cloud Credentials" \
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

run_cmd "2. Confirm No AWS Credentials in the Pod" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- \
env | grep -E '^AWS_' || echo '(no AWS_* environment variables)'"

run_cmd "3. Confirm No AWS Credentials in Kubernetes Secrets" \
  "kubectl get secret -n '$NS_SWA' -o json \
| jq '.items[].data | keys[] | select(test(\"AWS|aws\"))' \
|| echo '(no AWS credentials in any secret)'"

# ── Part 2: The SPIFFE Identity ───────────────────────────────────────────────

show_instruction "4. What the Workload Has Instead — A SPIFFE Identity" \
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

run_func "5. Fetch a Live JWT-SVID (audience: sts.amazonaws.com)" \
  "grpcurl -d '{\"audience\":[\"sts.amazonaws.com\"]}' unix:///tmp/swa-agent/public/api.sock SpiffeWorkloadAPI/FetchJWTSVID | decode claims" \
  fetch_spiffe_jwt_for_aws

# ── Part 3: The AWS Trust Chain ───────────────────────────────────────────────

show_instruction "6. How AWS Trusts This Identity — The OIDC Trust Chain" \
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

run_func "7. Show IAM OIDC Provider and Role Trust Policy" \
  "aws iam get-open-id-connect-provider && aws iam get-role --role-name $ROLE_NAME" \
  show_trust_policy

# ── Part 4: Live Access ───────────────────────────────────────────────────────

show_instruction "8. The Full Flow at Runtime" \
  "When giftapp-swa calls /csp-test?cloud=aws:

    1. Fetch JWT-SVID from SWA Agent socket  (audience: sts.amazonaws.com)
    2. POST to AWS STS AssumeRoleWithWebIdentity with the JWT
    3. STS validates JWT signature against the OIDC discovery endpoint
    4. STS checks aud and sub claims match the role trust policy
    5. STS returns temporary credentials (valid ~1 hour, never stored)
    6. Sign S3 GetObject request with SigV4 using those credentials
    7. Return the file contents

  Zero static credentials. Every access is freshly authenticated."

run_func "9. Call the Endpoint — Full SPIFFE → STS → S3 Flow" \
  "curl -sk https://localhost:8443/csp-test?cloud=aws | jq ." \
  csp_test_aws

# ── Part 5: Prove It Is a Live Fetch ─────────────────────────────────────────

show_instruction "10. Prove the Fetch Is Live — Edit the S3 File" \
  "We'll update test.txt directly in S3, then call the endpoint again.
  The response will immediately reflect the new content — proving the app
  fetches from S3 on every call with freshly-issued STS credentials.

  No cache. No stored token. Each call re-authenticates."

run_func "11. Update S3 File and Re-Fetch" \
  "echo 'updated by demo' | aws s3 cp - s3://$AWS_SPIFFE_BUCKET/test.txt && curl /csp-test?cloud=aws" \
  edit_and_refetch

# ── Part 6: Audit Trail ───────────────────────────────────────────────────────

show_instruction "12. Auditability — Every Access Is Traceable to a Workload" \
  "Because authentication goes through AWS STS, every S3 access generates
  a CloudTrail event for AssumeRoleWithWebIdentity.

  The event includes:
    - The IAM role assumed
    - The session name (spiffe-session)
    - The JWT-SVID used (decodable to reveal the SPIFFE ID)
    - Source IP, timestamp

  Security teams can answer: which workload accessed what, and when —
  with cryptographic proof of identity, not just a shared access key."

run_func "13. Show CloudTrail — AssumeRoleWithWebIdentity Events" \
  "aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity" \
  show_cloudtrail

# ── Closing ───────────────────────────────────────────────────────────────────

show_instruction "14. Summary" \
  "What we demonstrated:

  BEFORE (static credentials)
    - AWS keys stored in Kubernetes Secrets or environment variables
    - Stealable via pod exec, secret read, or etcd backup
    - No per-workload attribution in audit logs
    - Manual rotation required

  AFTER (SPIFFE identity federation)
    - No AWS credentials stored anywhere in the cluster
    - Workload proved its identity cryptographically at runtime
    - IAM role trust policy pinned to exact SPIFFE ID — not just namespace
    - Every access auditable in CloudTrail with workload-level attribution
    - Short-lived STS tokens expire automatically

  The only thing that grants AWS access is the workload's SPIFFE identity,
  issued by the SWA Server and verified by AWS via OIDC federation."
