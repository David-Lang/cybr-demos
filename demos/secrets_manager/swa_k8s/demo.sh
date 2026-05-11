#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

INTERACTIVE=false
OPEN_K9S=false

usage() {
  cat <<'EOF'
Usage: ./demo.sh [--interactive] [--k9s]

Runs the SWA Kubernetes demo walkthrough against an already deployed demo.

Options:
  -i, --interactive   Pause before each command or instruction.
  --k9s               Open k9s after the scripted walkthrough.
  -h, --help          Show this help.

Optional environment:
  DEMO_HOST           Public DNS name or IP to use for app URLs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive)
      INTERACTIVE=true
      ;;
    --k9s)
      OPEN_K9S=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[FAIL] unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -f /etc/profile.d/cyberark.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

if [[ -f "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" ]]; then
  # shellcheck disable=SC1091
  source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
fi

if [[ ! -f "$SCRIPT_DIR/setup/vars.env" ]]; then
  echo "[FAIL] missing setup/vars.env. Run this only after setup/deployment is complete." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup/vars.env"
if [[ -f "$SCRIPT_DIR/setup/swa/swa_registered.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/setup/swa/swa_registered.env"
fi
set +a

: "${LAB_ID:?LAB_ID is not set. Source tenant vars or export LAB_ID before running the demo.}"

NS_HARDCODED="${NAMESPACE_HARDCODED:-$LAB_ID-giftapp-hardcoded}"
NS_SWA="${NAMESPACE_SWA:-$LAB_ID-giftapp-swa}"
SWA_NS="${SWA_NAMESPACE:-swa-system}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[FAIL] required tool not found: $1" >&2
    exit 1
  fi
}

pause() {
  if [[ "$INTERACTIVE" == "true" ]]; then
    read -r -p "Press Enter to continue..."
  fi
}

section() {
  printf "\n=== %s ===\n" "$1"
}

run_cmd() {
  local title="$1"
  local cmd="$2"

  section "$title"
  printf "Command: %s\n\n" "$cmd"
  pause
  bash -c "$cmd"
}

show_instruction() {
  local title="$1"
  local body="$2"

  section "$title"
  printf "%s\n" "$body"
  pause
}

run_func() {
  local title="$1"
  local command_label="$2"
  local func_name="$3"

  section "$title"
  printf "Command: %s\n\n" "$command_label"
  pause
  "$func_name"
}

service_node_port() {
  kubectl get svc "$1" -n "$2" -o jsonpath='{.spec.ports[0].nodePort}'
}

detect_demo_host() {
  if [[ -n "${DEMO_HOST:-}" ]]; then
    printf '%s\n' "$DEMO_HOST"
    return
  fi

  local public_ip
  public_ip="$(curl -fsS --max-time 3 https://checkip.amazonaws.com/ 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "$public_ip" ]]; then
    printf 'ec2-%s.compute-1.amazonaws.com\n' "${public_ip//./-}"
    return
  fi

  local node_ip
  node_ip="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)"
  if [[ -z "$node_ip" ]]; then
    node_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi

  if [[ -n "$node_ip" ]]; then
    printf '%s\n' "$node_ip"
  else
    printf '<rancher-node-public-dns-or-ip>'
  fi
}

aws_edit_and_fetch() {
  local creds_file="$SCRIPT_DIR/setup/cloud/aws_credentials.env"
  local bucket region key_id secret

  bucket="$(kubectl get configmap giftapp-cloud-spiffe -n "$NS_SWA" \
    -o jsonpath='{.data.AWS_SPIFFE_BUCKET}')"
  region="$(kubectl get configmap giftapp-cloud-spiffe -n "$NS_SWA" \
    -o jsonpath='{.data.AWS_SPIFFE_REGION}')"
  key_id="$(grep AWS_ACCESS_KEY_ID "$creds_file" | cut -d'"' -f2)"
  secret="$(grep AWS_SECRET_ACCESS_KEY "$creds_file" | cut -d'"' -f2)"

  echo "updated by demo - $(date -u +%H:%M:%SZ)" \
    | AWS_ACCESS_KEY_ID="$key_id" AWS_SECRET_ACCESS_KEY="$secret" \
      AWS_DEFAULT_REGION="$region" \
      aws s3 cp - "s3://$bucket/test.txt"

  kubectl exec -n "$NS_SWA" deploy/giftapp-swa -- \
    wget -qO- --no-check-certificate "https://127.0.0.1:8443/csp-test?cloud=aws" | jq .
}

fetch_fresh_jwt_svid() {
  local pod
  pod="$(kubectl get pods -n "$NS_SWA" -l app=giftapp-swa \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"

  if [[ -z "$pod" ]]; then
    echo "[FAIL] no Running giftapp-swa pod found" >&2
    exit 1
  fi

  local response
  response="$(kubectl exec -i -n "$NS_SWA" "pod/$pod" -- sh <<'POD_SCRIPT'
set -euo pipefail

grpcurl_version="${GRPCURL_VERSION:-1.9.3}"
grpcurl_url="https://github.com/fullstorydev/grpcurl/releases/download/v${grpcurl_version}/grpcurl_${grpcurl_version}_linux_x86_64.tar.gz"

cd /tmp
if [ ! -x /tmp/grpcurl ]; then
  wget -qO- "$grpcurl_url" | tar -xz grpcurl
  chmod +x /tmp/grpcurl
fi

cat > /tmp/workloadapi.proto <<'EOF_PROTO'
syntax = "proto3";

service SpiffeWorkloadAPI {
  rpc FetchJWTSVID(JWTSVIDRequest) returns (JWTSVIDResponse);
}

message JWTSVIDRequest {
  repeated string audience = 1;
  string spiffe_id = 2;
}

message JWTSVIDResponse {
  repeated JWTSVID svids = 1;
}

message JWTSVID {
  string spiffe_id = 1;
  string svid = 2;
  string hint = 3;
}
EOF_PROTO

/tmp/grpcurl \
  -plaintext \
  -H 'workload.spiffe.io: true' \
  -import-path /tmp \
  -proto workloadapi.proto \
  -d '{"audience":["conjur"]}' \
  unix:///tmp/swa-agent/public/api.sock \
  SpiffeWorkloadAPI/FetchJWTSVID
POD_SCRIPT
)"

  printf '%s\n' "$response" | jq '
    def b64url_json:
      gsub("-"; "+")
      | gsub("_"; "/")
      | . + (["", "===", "==", "="][length % 4])
      | @base64d
      | fromjson;

    . as $response
    | ($response.svids[0].svid | split(".")) as $parts
    | {
        workloadApiResponse: $response,
        decodedJwt: {
          header: ($parts[0] | b64url_json),
          payload: ($parts[1] | b64url_json),
          signature: $parts[2]
        }
      }
  '
}

require_tool kubectl
require_tool jq
require_tool curl

hardcoded_port="$(service_node_port giftapp-hardcoded "$NS_HARDCODED")"
swa_port="$(service_node_port giftapp-swa "$NS_SWA")"
demo_host="$(detect_demo_host)"
hardcoded_url="https://${demo_host}:${hardcoded_port}"
swa_url="https://${demo_host}:${swa_port}"

cat <<EOF
SWA Kubernetes Demo

This walkthrough assumes setup and deployment are already complete.

Namespaces:
  SWA system:    $SWA_NS
  Vulnerable app: $NS_HARDCODED
  Secured app:    $NS_SWA

Interactive mode: $INTERACTIVE
Browser host:     $demo_host
EOF

pause

# ── Part 1: The Vulnerable App ───────────────────────────────────────────────

run_cmd "1. Check Deployment Status" \
  "kubectl get pods -n '$SWA_NS' && kubectl get pods -n '$NS_HARDCODED' && kubectl get pods -n '$NS_SWA'"

run_cmd "2. Query The Vulnerable App" \
  "curl -sk '$hardcoded_url' | jq ."

show_instruction "3. How The Vulnerable App Gets Its Secrets" \
  "The deployment declares a volume backed by a Kubernetes Secret:

    volumes:
      - name: secret-volume
        secret:
          secretName: giftapp-hardcoded-secrets   # All credentials stored in etcd

    volumeMounts:
      - name: secret-volume
        mountPath: /etc/secrets                   # Every key becomes a file here
        readOnly: true

  The Kubernetes Secret contains: DB_USER, DB_PASS, DB_HOST, DB_PORT, DB_NAME, GIFTAPP_API_KEY.
  All values are base64-encoded in etcd and readable by anyone with access to the pod
  or the Secret object."

run_cmd "4. Read Credentials From Inside The Vulnerable Pod" \
  "kubectl exec -n '$NS_HARDCODED' deploy/giftapp-hardcoded -- sh -c 'printf \"API KEY: \"; cat /etc/secrets/GIFTAPP_API_KEY; echo; printf \"DB PASS: \"; cat /etc/secrets/DB_PASS; echo'"

run_cmd "5. Read The Kubernetes Secret Directly Via The Pod Service Account Token" \
  "SA_TOKEN=\$(kubectl exec -n '$NS_HARDCODED' deploy/giftapp-hardcoded -- cat /var/run/secrets/kubernetes.io/serviceaccount/token); kubectl get secret giftapp-hardcoded-secrets -n '$NS_HARDCODED' --token=\"\$SA_TOKEN\" -o jsonpath='{.data}' | jq 'to_entries[] | \"\\(.key): \\(.value | @base64d)\"' -r"

show_instruction "6. Why The Service Account Can Do That" \
  "The deployment's RBAC grants the service account get/list on the Secret:

    kind: Role
    rules:
      - resources: [\"secrets\"]
        resourceNames: [\"giftapp-hardcoded-secrets\"]
        verbs: [\"get\", \"list\"]

  That grant exists because the app needs the secret at startup — but it also means any
  process that steals the pod's service account token can read the credentials directly
  from the Kubernetes API, without ever touching the pod filesystem."

# ── Part 2: Volume Architecture Comparison ───────────────────────────────────

show_instruction "7. How The Secured App Gets Its Secrets — Volume Architecture" \
  "The SWA deployment replaces the sensitive secret volume with a socket:

  Vulnerable app                         Secured app
  ─────────────────────────────────────  ──────────────────────────────────────────
  volumes:                               volumes:
    - name: secret-volume                  - name: secret-volume
      secret:                                secret:
        secretName:                            secretName:
          giftapp-hardcoded-secrets              giftapp-swa-secrets  # no passwords
                                           - name: swa-socket         # NEW
                                             hostPath:
                                               path: /tmp/swa-agent/public
  volumeMounts:                          volumeMounts:
    - name: secret-volume                  - name: secret-volume
      mountPath: /etc/secrets                mountPath: /etc/secrets
                                           - name: swa-socket         # NEW
                                             mountPath: /tmp/swa-agent/public
                                             readOnly: true

  The swa-socket hostPath exposes the SWA agent Unix socket from the node into the
  container. Instead of reading a file for sensitive credentials, the app calls the
  socket at runtime to prove its identity and fetch the secrets from Conjur."

run_cmd "8. Show What Is In The Secured App Kubernetes Secret" \
  "kubectl get secret giftapp-swa-secrets -n '$NS_SWA' -o json | jq '.data | keys'"

show_instruction "9. What Is Missing From The Secured App Kubernetes Secret And Why" \
  "The SWA Kubernetes Secret contains only non-sensitive connection config:
    DB_USER, DB_HOST, DB_PORT, DB_NAME

  DB_PASS and GIFTAPP_API_KEY are absent. They are never stored in Kubernetes.
  The app fetches them at runtime through the SWA socket using a SPIFFE JWT-SVID."

run_cmd "10. Confirm No Sensitive Files At /etc/secrets In The Secured Pod" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- ls -1 /etc/secrets/"

run_cmd "11. Show The SWA Socket Mounted In The Secured Pod" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- ls -l '${SWA_SOCKET_PATH:-/tmp/swa-agent/public/api.sock}'"

# ── Part 3: The SWA Runtime Flow ─────────────────────────────────────────────

run_cmd "12. Show SWA Agent And Server Are Running" \
  "kubectl get deployment swa-server -n '$SWA_NS' && kubectl get daemonset swa-agent -n '$SWA_NS' && kubectl get pods -n '$SWA_NS'"

run_func "13. Fetch A Fresh JWT-SVID From The Workload API Socket" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- grpcurl -H 'workload.spiffe.io: true' unix:///tmp/swa-agent/public/api.sock SpiffeWorkloadAPI/FetchJWTSVID | jq ." \
  fetch_fresh_jwt_svid

run_cmd "14. Show The SPIFFE Authentication Result In The App Logs" \
  "kubectl logs -n '$NS_SWA' deploy/giftapp-swa --tail=80 | grep -E 'jwt-svid claims|loaded secrets through SWA'"

run_cmd "15. Force Fresh SWA Authentication Without A Pod Restart" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- wget -qO- --no-check-certificate --post-data='' https://127.0.0.1:8443/refresh | jq ."

run_cmd "16. Query The Secured App" \
  "curl -sk '$swa_url' | jq ."

run_cmd "17. Show SWA Health And Live Secret Retrieval" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- wget -qO- --no-check-certificate https://127.0.0.1:8443/healthz | jq ."

# ── Part 4: Cloud Federation with SPIFFE JWT-SVIDs ───────────────────────────

AWS_ROLE_ARN=""
if kubectl get configmap giftapp-cloud-spiffe -n "$NS_SWA" &>/dev/null; then
  AWS_ROLE_ARN="$(kubectl get configmap giftapp-cloud-spiffe -n "$NS_SWA" \
    -o jsonpath='{.data.AWS_SPIFFE_ROLE_ARN}' 2>/dev/null || true)"
fi

if [[ -n "$AWS_ROLE_ARN" ]]; then
  show_instruction "18. Cloud Federation — SPIFFE Identity as an AWS Credential" \
    "The same JWT-SVID used to authenticate to Conjur can also federate with AWS IAM.
  No AWS credentials are ever stored in the cluster.

  Flow:
    1. giftapp-swa fetches a JWT-SVID from the SWA Agent (audience: sts.amazonaws.com)
    2. AWS STS validates the JWT signature via the SWA Server's OIDC discovery endpoint
    3. STS checks the JWT claims match the IAM role trust policy (issuer + subject)
    4. STS returns temporary AWS credentials (valid ~1 hour)
    5. The app uses those credentials to sign an S3 GetObject request (SigV4, no AWS SDK)

  The IAM role trust policy pins to the exact SPIFFE ID of giftapp-swa:
    Condition: StringEquals
      \${OIDC_ISSUER}:sub: spiffe://.../.../giftapp-swa-sa
      \${OIDC_ISSUER}:aud: sts.amazonaws.com

  AWS role: $AWS_ROLE_ARN"

  run_cmd "19. Test AWS S3 Access via SPIFFE JWT-SVID" \
    "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- \
wget -qO- --no-check-certificate 'https://127.0.0.1:8443/csp-test?cloud=aws' | jq ."

  run_func "20. Edit The S3 File To Prove It Is A Live Fetch" \
    "echo 'updated by demo - \$(date -u)' | aws s3 cp - s3://<bucket>/test.txt && curl /csp-test?cloud=aws" \
    aws_edit_and_fetch
fi

# ── Part 5: Summary ───────────────────────────────────────────────────────────

show_instruction "$( [[ -n "$AWS_ROLE_ARN" ]] && echo "21" || echo "18" ). Summary" \
  "The core difference is in how volumes deliver credentials:

  giftapp-hardcoded
    secret-volume → giftapp-hardcoded-secrets (Kubernetes Secret in etcd)
    Contains: DB_PASS, GIFTAPP_API_KEY, and all connection config
    Attack surface: pod exec reads files, SA token reads Secret via Kubernetes API

  giftapp-swa
    secret-volume → giftapp-swa-secrets (non-sensitive config only, no passwords)
    swa-socket    → hostPath to SWA agent Unix socket on the node
    Sensitive values never touch etcd. The app proves its identity with a SPIFFE
    JWT-SVID and Conjur delivers the credentials at runtime through the socket."

if [[ "$OPEN_K9S" == "true" ]]; then
  require_tool k9s
  show_instruction "Open k9s" "k9s will open after you press Enter."
  k9s
fi
