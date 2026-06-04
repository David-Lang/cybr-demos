#!/bin/bash
# setup/edge/import_edge_cert.sh — extract Edge's self-signed TLS cert and
# import it into the cybr-jenkins container's Java truststore so that the
# Jenkins Conjur plugin can call Edge over HTTPS without TLS errors.
#
# Idempotent. Safe to re-run after Edge restart / cert rotation.
set -euo pipefail

demo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$demo_dir/jenkins_demo_lib.sh"
jenkins_demo_init
jenkins_load_env

EDGE_CONTAINER="${EDGE_CONTAINER:-cybr-conjur-edge}"
EDGE_PORT="${EDGE_PORT:-443}"
JENKINS_CONTAINER="${JENKINS_CONTAINER:-cybr-jenkins}"
ALIAS="${EDGE_CERT_ALIAS:-cybr-conjur-edge}"

log()  { printf '\033[36m[edge/cert]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[edge/cert ERR]\033[0m %s\n' "$*" >&2; }

if ! jenkins_container_running; then
  err "Jenkins container $JENKINS_CONTAINER is not running."
  exit 1
fi

if ! edge_container_running; then
  err "Edge container $EDGE_CONTAINER is not running."
  exit 1
fi

# Pull the live cert from Edge via the host-bound port. Edge's TLS terminates
# on the container's 8443, mapped to host EDGE_PORT (default 443).
log "Fetching cert from https://127.0.0.1:${EDGE_PORT}"
pem_file=$(mktemp /tmp/edge-cert.XXXXXX.pem)
trap 'rm -f "$pem_file"' EXIT
if ! echo | openssl s_client -showcerts -connect "127.0.0.1:${EDGE_PORT}" 2>/dev/null \
     | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "$pem_file"; then
  err "openssl s_client failed against 127.0.0.1:${EDGE_PORT}"
  exit 1
fi
if [[ ! -s "$pem_file" ]]; then
  err "Empty cert from 127.0.0.1:${EDGE_PORT}. Edge TLS may not be ready yet."
  exit 1
fi
log "Extracted $(grep -c 'BEGIN CERTIFICATE' "$pem_file") cert(s)"

# Copy into Jenkins and re-import (delete-then-import for idempotency).
log "Importing into $JENKINS_CONTAINER Java truststore (alias=$ALIAS)"
docker cp "$pem_file" "${JENKINS_CONTAINER}:/tmp/edge-import.pem" >/dev/null
docker exec -u root "$JENKINS_CONTAINER" bash -c "
set -euo pipefail
keytool -delete -alias '${ALIAS}' \
  -keystore /opt/java/openjdk/lib/security/cacerts \
  -storepass changeit -noprompt 2>/dev/null || true
keytool -importcert -alias '${ALIAS}' \
  -keystore /opt/java/openjdk/lib/security/cacerts \
  -file /tmp/edge-import.pem -storepass changeit -noprompt
rm -f /tmp/edge-import.pem
"

log "Restarting Jenkins to pick up the new truststore"
docker restart "$JENKINS_CONTAINER" >/dev/null
log "Wait ~30s for Jenkins to be ready, then run: bash finish_setup.sh"
