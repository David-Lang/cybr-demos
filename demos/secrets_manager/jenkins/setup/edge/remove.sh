#!/bin/bash
# setup/edge/remove.sh — tear down the Conjur Cloud Edge container.
#
# Does NOT remove the Edge instance from the Secrets Manager UI — that requires
# manual cleanup in the SaaS console (Edges -> ... -> Delete).
set -euo pipefail

demo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$demo_dir/jenkins_demo_lib.sh"
jenkins_demo_init
jenkins_load_env

EDGE_CONTAINER="${EDGE_CONTAINER:-cybr-conjur-edge}"
EDGE_DATA_DIR="$(edge_resolved_data_dir)"

log()  { printf '\033[36m[edge/remove]\033[0m %s\n' "$*"; }

if docker ps -a --format '{{.Names}}' | grep -qx "$EDGE_CONTAINER"; then
  log "Removing container $EDGE_CONTAINER"
  docker rm -f "$EDGE_CONTAINER" >/dev/null
else
  log "No container named $EDGE_CONTAINER present"
fi

if [[ -d "$EDGE_DATA_DIR" ]]; then
  log "Persistence dir kept at $EDGE_DATA_DIR"
  log "  To wipe: sudo rm -rf $EDGE_DATA_DIR"
fi

log "Note: also delete the Edge instance in the Secrets Manager UI (Edges page)"
log "      if you don't plan to reuse it. The SaaS UI does not auto-clean."
