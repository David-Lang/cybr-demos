#!/bin/bash
# Shared helpers for the SWA (Secure Workload Access) Kubernetes demo.
# Source this from the demo scripts; do not execute directly.
# shellcheck disable=SC2034  # vars are consumed by sourcing scripts

# Resolve the demo root (directory containing this lib) and repo root.
SWA_DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SWA_DEMO_DIR
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SWA_DEMO_DIR/../../../.." && pwd)}"

# Extracted release lives here (gitignored). load_release.sh populates it.
export SWA_RELEASE_ROOT="$SWA_DEMO_DIR/setup/swa/release"
export SWA_PLUGIN_MIRROR="$SWA_DEMO_DIR/setup/swa/plugin-mirror"
export SWA_TFRC="$SWA_DEMO_DIR/setup/swa/.terraformrc"

# Load tenant credentials, shared helpers, and demo vars.env.
swa_demo_init() {
  set -a
  # shellcheck source=/dev/null
  source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
  if [[ -f "$SWA_DEMO_DIR/setup/vars.env" ]]; then
    # shellcheck source=/dev/null
    source "$SWA_DEMO_DIR/setup/vars.env"
  else
    echo "[ERROR] Missing $SWA_DEMO_DIR/setup/vars.env — copy from setup/vars.env.example" >&2
    return 1
  fi
  set +a

  # Derived identity values used across templates.
  export SWA_SPIFFE_ID="spiffe://${SWA_TRUST_DOMAIN}/${SWA_NODE_GROUP}/ns/${SWA_APP_NAMESPACE}/sa/${SWA_APP_SA}"
  export SM_FQDN="${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud"
}

# Map host architecture to the release's image tag suffix and provider dir suffix.
swa_arch_image_suffix() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64v8" ;;
    x86_64|amd64)  echo "amd64" ;;
    *) echo "amd64" ;;
  esac
}

swa_arch_tf_suffix() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux)  os="linux" ;;
    *)      os="linux" ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    *)             arch="amd64" ;;
  esac
  echo "${os}_${arch}"
}

# Populate release artifact paths (charts, image tars/tags, terraform provider).
# Requires the release to be extracted under $SWA_RELEASE_ROOT.
swa_release_paths() {
  local img_suffix tf_suffix
  img_suffix="$(swa_arch_image_suffix)"
  tf_suffix="$(swa_arch_tf_suffix)"

  export SWA_CHART_SERVER="$SWA_RELEASE_ROOT/helm/swa-server-0.1.0.tgz"
  export SWA_CHART_AGENT="$SWA_RELEASE_ROOT/helm/swa-agent-0.1.0.tgz"
  export SWA_IMG_SERVER_TAR="$SWA_RELEASE_ROOT/container-images/swa-server-1.0.0-${img_suffix}.tar"
  export SWA_IMG_AGENT_TAR="$SWA_RELEASE_ROOT/container-images/swa-agent-1.0.0-${img_suffix}.tar"
  export SWA_IMG_SERVER="swa-server:1.0.0-${img_suffix}"
  export SWA_IMG_AGENT="swa-agent:1.0.0-${img_suffix}"

  local tf_dir tf_bin
  tf_dir="$(find "$SWA_RELEASE_ROOT/terraform-provider" -maxdepth 1 -type d -name "*_${tf_suffix}" 2>/dev/null | head -1)"
  tf_bin="$(find "$tf_dir" -maxdepth 1 -type f -name 'terraform-provider-swa_v*' 2>/dev/null | head -1)"
  export SWA_TF_PROVIDER_DIR="$tf_dir"
  export SWA_TF_PROVIDER_BIN="$tf_bin"
}

# Resolve the SWA release zip path. Treats an empty SWA_RELEASE_DIR as unset.
swa_release_zip_path() {
  local zip_path release_dir
  zip_path="${SWA_RELEASE_ZIP:-}"
  if [[ -n "$zip_path" && -f "$zip_path" ]]; then
    printf '%s' "$zip_path"
    return 0
  fi
  release_dir="${SWA_RELEASE_DIR:-}"
  [[ -n "$release_dir" ]] || release_dir="$HOME/Downloads"
  find "$release_dir" -maxdepth 1 -name 'Secure Workload Access*.zip' -print 2>/dev/null \
    | sort | tail -1 || true
}

# Extract a raw JWT-SVID string from swa-agent JSON output.
swa_extract_svid_from_json() {
  jq -r '
    (.. | objects | select(has("svid")) | .svid) //
    (if type=="array" then .[0] else . end | (.token // .jwt))
  ' 2>/dev/null | head -1
}

# Read the workload pod's JWT-SVID from /spiffe/svid.json (empty on failure).
swa_read_workload_svid() {
  local deploy="${1:-swa-demo-app}" container="${2:-app}"
  local j
  j="$(kubectl exec -n "$SWA_APP_NAMESPACE" deploy/"$deploy" -c "$container" -- \
    cat /spiffe/svid.json 2>/dev/null || true)"
  [[ -n "$j" ]] || return 1
  printf '%s' "$j" | swa_extract_svid_from_json
}

# Return 0 when the JWT payload exp is in the past (or unparsable).
swa_svid_is_expired() {
  local svid="$1" payload_b64 exp now
  [[ "$svid" == *.*.* ]] || return 0
  payload_b64="${svid#*.}"; payload_b64="${payload_b64%%.*}"
  exp="$(printf '%s' "$payload_b64" | tr '_-' '/+' \
    | { p="$(cat)"; pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s%*s' "$p" "$pad" '' | tr ' ' '='; } \
    | base64 -d 2>/dev/null | jq -r '.exp' 2>/dev/null || true)"
  [[ "$exp" =~ ^[0-9]+$ ]] || return 0
  now="$(date +%s)"
  (( now >= exp ))
}

# Restart the workload so the init container fetches a fresh JWT-SVID.
swa_refresh_workload_svid() {
  local deploy="${1:-swa-demo-app}" i
  kubectl rollout restart deployment/"$deploy" -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1 || return 1
  kubectl rollout status deployment/"$deploy" -n "$SWA_APP_NAMESPACE" --timeout=120s >/dev/null 2>&1 || return 1
  for i in $(seq 1 12); do
    swa_read_workload_svid "$deploy" app >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}

# Return a usable JWT-SVID, restarting the workload when the on-disk token is expired.
swa_get_live_workload_svid() {
  local deploy="${1:-swa-demo-app}" svid
  svid="$(swa_read_workload_svid "$deploy" app 2>/dev/null || true)"
  if [[ "$svid" == *.*.* ]] && ! swa_svid_is_expired "$svid"; then
    printf '%s' "$svid"
    return 0
  fi
  swa_refresh_workload_svid "$deploy" || return 1
  swa_read_workload_svid "$deploy" app
}

# Return 0 when the SWA control plane is healthy: server ready, agent ready, and
# no expired-certificate errors in recent agent logs. The expired-cert case is
# common after the laptop sleeps — the server's serving cert ages out, the agent
# can no longer attest or mint SVIDs, and workload init containers crash-loop.
swa_control_plane_healthy() {
  kubectl get deploy/swa-server -n "$SWA_NAMESPACE" >/dev/null 2>&1 || return 1
  [[ "$(kubectl get deploy/swa-server -n "$SWA_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" == "1" ]] || return 1
  local desired ready
  desired="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
  ready="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
  [[ "${desired:-0}" -gt 0 && "${ready:-0}" == "${desired:-0}" ]] || return 1
  if kubectl logs -n "$SWA_NAMESPACE" ds/swa-agent --tail=30 2>/dev/null | grep -qi "expired certificate"; then
    return 1
  fi
  return 0
}

# Restart the SWA control plane (server then agent) to re-bootstrap fresh certs.
# Idempotent; safe to call when already healthy.
swa_heal_control_plane() {
  kubectl rollout restart deploy/swa-server -n "$SWA_NAMESPACE" >/dev/null 2>&1 || true
  kubectl rollout status  deploy/swa-server -n "$SWA_NAMESPACE" --timeout=180s >/dev/null 2>&1 || true
  kubectl rollout restart ds/swa-agent     -n "$SWA_NAMESPACE" >/dev/null 2>&1 || true
  kubectl rollout status  ds/swa-agent     -n "$SWA_NAMESPACE" --timeout=180s >/dev/null 2>&1 || true
}

# Acquire an ISPSS identity token and exchange it for a Conjur Cloud access token.
# Sets SWA_IDENTITY_TOKEN and SWA_CONJUR_TOKEN.
swa_get_tokens() {
  SWA_IDENTITY_TOKEN="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
  [[ -n "$SWA_IDENTITY_TOKEN" ]] || { echo "[ERROR] Failed to get identity token" >&2; return 1; }
  SWA_CONJUR_TOKEN="$(get_conjur_token "$TENANT_SUBDOMAIN" "$SWA_IDENTITY_TOKEN")"
  [[ -n "$SWA_CONJUR_TOKEN" ]] || { echo "[ERROR] Failed to get Conjur token" >&2; return 1; }
  export SWA_IDENTITY_TOKEN SWA_CONJUR_TOKEN
}
