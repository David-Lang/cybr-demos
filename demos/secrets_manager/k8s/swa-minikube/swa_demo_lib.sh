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

# Acquire an ISPSS identity token and exchange it for a Conjur Cloud access token.
# Sets SWA_IDENTITY_TOKEN and SWA_CONJUR_TOKEN.
swa_get_tokens() {
  SWA_IDENTITY_TOKEN="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
  [[ -n "$SWA_IDENTITY_TOKEN" ]] || { echo "[ERROR] Failed to get identity token" >&2; return 1; }
  SWA_CONJUR_TOKEN="$(get_conjur_token "$TENANT_SUBDOMAIN" "$SWA_IDENTITY_TOKEN")"
  [[ -n "$SWA_CONJUR_TOKEN" ]] || { echo "[ERROR] Failed to get Conjur token" >&2; return 1; }
  export SWA_IDENTITY_TOKEN SWA_CONJUR_TOKEN
}
