#!/bin/bash
# setup/edge/setup.sh — bring up Conjur Cloud Edge and wait until it is healthy.
#
# What it does:
#   1. Verifies CyberArk's `localhost/cyberark/edge:*` image is loaded locally.
#   2. Creates the Edge persistence dir (macOS-aware: uses $HOME/cyberark).
#   3. Removes any prior Edge container with the same name.
#   4. Sources the user-saved SaaS install script (setup/edge/install.sh) which
#      contains the one-shot 8-minute install token + the docker run command.
#   5. Waits for the container to be running and the /health endpoint to respond.
#   6. Imports the Edge self-signed cert into the cybr-jenkins Java truststore.
#
# Pre-reqs the user must do manually before running this:
#   - Download the Edge image from CyberArk Marketplace and run `docker load`.
#   - Create the Edge instance in the Secrets Manager UI Edges page (set
#     COMMON_NAME=host.docker.internal so the cert validates from inside Jenkins).
#   - Save the generated install script as setup/edge/install.sh.
#
# Idempotent. Safe to re-run.
set -euo pipefail

demo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$demo_dir/jenkins_demo_lib.sh"
jenkins_demo_init
jenkins_load_env

EDGE_CONTAINER="${EDGE_CONTAINER:-cybr-conjur-edge}"
EDGE_HOST="${EDGE_HOST:-host.docker.internal}"
EDGE_PORT="${EDGE_PORT:-443}"
EDGE_HEALTH_PORT="${EDGE_HEALTH_PORT:-444}"
EDGE_INSTALL_SCRIPT="${EDGE_INSTALL_SCRIPT:-$JENKINS_EDGE_INSTALL}"
EDGE_DATA_DIR="$(edge_resolved_data_dir)"

log()  { printf '\033[36m[edge/setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[edge/setup WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[edge/setup ERR]\033[0m %s\n' "$*" >&2; }

require_image() {
  if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q '^localhost/cyberark/edge:'; then
    err "Conjur Cloud Edge image not loaded into Docker."
    err "Download conjur-edge_<version>.tar.gz from the CyberArk Marketplace:"
    err "  https://community.cyberark.com/marketplace/s/#software-aK4Vy000000004rKAA-"
    err "Then load it:"
    err "  sudo docker load -i ~/Downloads/conjur-edge_*.tar.gz"
    err "Then re-run: bash setup/edge/setup.sh"
    exit 1
  fi
  log "Edge image present: $(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^localhost/cyberark/edge:' | head -1)"
}

require_install_script() {
  if [[ ! -f "$EDGE_INSTALL_SCRIPT" ]]; then
    err "Edge install script not found: $EDGE_INSTALL_SCRIPT"
    err ""
    err "Get one from the Secrets Manager UI:"
    err "  Edges -> Install new Edge"
    err "  COMMON_NAME=host.docker.internal   (so cert validates from Jenkins)"
    err "  SAN=127.0.0.1,localhost"
    err "  Persistence folder=\$HOME/cyberark   (macOS) or /cyberark (Linux)"
    err ""
    err "Copy the generated script and save it as:"
    err "  $EDGE_INSTALL_SCRIPT"
    err ""
    err "On macOS, replace any '/cyberark' in the script with '\$HOME/cyberark'"
    err "before saving (root of / is read-only on macOS)."
    err ""
    err "The token inside the script expires 8 minutes after generation. Run quickly."
    exit 1
  fi
  log "Install script: $EDGE_INSTALL_SCRIPT"
}

prepare_data_dir() {
  log "Persistence dir: $EDGE_DATA_DIR"
  mkdir -p "$EDGE_DATA_DIR"
  # uid 5000 is the Edge container user. On macOS this number won't match any
  # real user, but Docker Desktop's bind-mount layer should map it correctly.
  if ! sudo chown -R 5000:5000 "$EDGE_DATA_DIR" 2>/dev/null; then
    warn "Could not chown $EDGE_DATA_DIR to 5000:5000 (may need sudo)"
  fi
  # Docker Desktop on macOS occasionally fails to honor uid:gid through its
  # bind-mount layer even after a successful chown — the in-container view
  # presents the dir as unwritable and Edge panics on logging init with
  # "mkdir /opt/edge/data/logs: permission denied". Sledgehammer chmod 777
  # avoids this entirely. Demo dir on a laptop, not security-sensitive.
  if ! sudo chmod -R 777 "$EDGE_DATA_DIR" 2>/dev/null; then
    warn "Could not chmod 777 $EDGE_DATA_DIR (may need sudo)"
  fi
}

remove_prior_container() {
  if docker ps -a --format '{{.Names}}' | grep -qx "$EDGE_CONTAINER"; then
    log "Removing prior Edge container: $EDGE_CONTAINER"
    docker rm -f "$EDGE_CONTAINER" >/dev/null
  fi
}

run_install() {
  log "Running install script (token expires 8 min after SaaS UI generation)..."
  # The script CyberArk hands you may use 'sudo' internally. We let it run as-is.
  bash "$EDGE_INSTALL_SCRIPT"
}

wait_for_running() {
  log "Waiting up to 60s for $EDGE_CONTAINER to be running..."
  local i
  for i in $(seq 1 30); do
    if edge_container_running; then
      log "Container is running ($i x 2s waited)"
      return 0
    fi
    sleep 2
  done
  err "$EDGE_CONTAINER did not reach running state in 60s"
  docker logs "$EDGE_CONTAINER" 2>&1 | tail -40 || true
  exit 1
}

wait_for_health() {
  log "Waiting up to 5 min for Edge /health to respond + initial replication to complete..."
  local i
  for i in $(seq 1 60); do
    if edge_health_ok; then
      log "Edge healthy after $((i * 5))s"
      return 0
    fi
    sleep 5
  done
  warn "Edge /health did not respond within 5 min."
  warn "Last 40 log lines from $EDGE_CONTAINER:"
  docker logs "$EDGE_CONTAINER" 2>&1 | tail -40 || true
  exit 1
}

import_cert_into_jenkins() {
  if ! jenkins_container_running; then
    warn "Jenkins container ${JENKINS_CONTAINER:-cybr-jenkins} not running — skipping cert import."
    warn "Run 'bash setup/edge/import_edge_cert.sh' after Jenkins is up."
    return 0
  fi
  log "Importing Edge cert into Jenkins Java truststore"
  bash "$JENKINS_EDGE_DIR/import_edge_cert.sh"
}

main() {
  log "Demo dir:      $JENKINS_DEMO_DIR"
  log "Edge container: $EDGE_CONTAINER"
  log "Edge URL:       $(edge_appliance_url)"
  log "Health URL:     http://127.0.0.1:${EDGE_HEALTH_PORT}/health"

  require_image
  require_install_script
  prepare_data_dir
  remove_prior_container
  run_install
  wait_for_running
  wait_for_health
  import_cert_into_jenkins

  log "Edge is up and healthy."
  log "Next: set CONJUR_AUTH_TARGET=edge and JWT_TRUST_MODE=jwks-uri in setup/vars.env,"
  log "      then run: bash configure_jenkins.sh && bash finish_setup.sh"
}

main "$@"
