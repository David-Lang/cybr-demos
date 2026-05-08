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
  SWA system:   $SWA_NS
  Attack app:   $NS_HARDCODED
  Defended app: $NS_SWA

Interactive mode: $INTERACTIVE
Browser host:     $demo_host
EOF

pause

run_cmd "1. Check Deployment Status" \
  "kubectl get pods -n '$SWA_NS' && kubectl get pods -n '$NS_HARDCODED' && kubectl get pods -n '$NS_SWA'"

run_cmd "2. Query The Vulnerable App" \
  "curl -sk '$hardcoded_url' | jq ."

run_cmd "3. Show Secrets Mounted In The Vulnerable Pod" \
  "kubectl exec -n '$NS_HARDCODED' deploy/giftapp-hardcoded -- sh -c 'printf \"API KEY: \"; cat /etc/secrets/GIFTAPP_API_KEY; echo; printf \"DB PASS: \"; cat /etc/secrets/DB_PASS; echo'"

run_cmd "4. Show The Vulnerable Service Account Can Read The Kubernetes Secret" \
  "SA_TOKEN=\$(kubectl exec -n '$NS_HARDCODED' deploy/giftapp-hardcoded -- cat /var/run/secrets/kubernetes.io/serviceaccount/token); kubectl get secret giftapp-hardcoded-secrets -n '$NS_HARDCODED' --token=\"\$SA_TOKEN\" -o jsonpath='{.data}' | jq 'to_entries[] | \"\\(.key): \\(.value | @base64d)\"' -r"

run_cmd "5. Query The Defended App" \
  "curl -sk '$swa_url' | jq ."

run_cmd "6. Show The Defended Pod Has No Sensitive Secret Files" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- ls /etc/secrets/ && kubectl get secret giftapp-swa-secrets -n '$NS_SWA' -o json | jq '.data | keys'"

run_cmd "7. Show The SWA Workload API Socket" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- ls -l '${SWA_SOCKET_PATH:-/tmp/swa-agent/public/api.sock}'"

run_cmd "8. Show SWA Agent And Server Are Running" \
  "kubectl get deployment swa-server -n '$SWA_NS' && kubectl get daemonset swa-agent -n '$SWA_NS' && kubectl get pods -n '$SWA_NS'"

run_cmd "9. Force Fresh SWA Authentication" \
  "kubectl rollout restart deployment/giftapp-swa -n '$NS_SWA' && kubectl rollout status deployment/giftapp-swa -n '$NS_SWA' --timeout=180s"

run_cmd "10. Show SWA Health And Secret Retrieval" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- wget -qO- --no-check-certificate https://127.0.0.1:8443/healthz | jq ."

run_func "11. Fetch A Fresh JWT-SVID From The Workload API Socket" \
  "kubectl exec -n '$NS_SWA' deploy/giftapp-swa -- grpcurl -H 'workload.spiffe.io: true' unix:///tmp/swa-agent/public/api.sock SpiffeWorkloadAPI/FetchJWTSVID | jq ." \
  fetch_fresh_jwt_svid

run_cmd "12. Show The SPIFFE Authentication Result In The App Logs" \
  "kubectl logs -n '$NS_SWA' deploy/giftapp-swa --tail=80 | grep -E 'jwt-svid claims|loaded secrets through SWA'"

show_instruction "13. Wrap Up" \
  "The comparison is:

  giftapp-hardcoded stores secrets in Kubernetes and exposes them to pod exec and Kubernetes API reads.
  giftapp-swa uses a Kubernetes-attested SPIFFE JWT-SVID from SWA, authenticates to Conjur, and keeps sensitive values out of Kubernetes Secret mounts."

if [[ "$OPEN_K9S" == "true" ]]; then
  require_tool k9s
  show_instruction "Open k9s" "k9s will open after you press Enter."
  k9s
fi
