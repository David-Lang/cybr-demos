#!/usr/bin/env bash
# Activity setup: stand up the VM-local Postgres the student will query.
#
# This runs as part of ACTIVITY SETUP (deployment/enablement), not the activity
# itself. It brings up a local Postgres container with an INITIAL credential
# (the one the hardcoded query script uses and the student later vaults), seeds
# the demo table, and makes the database PORT-ACCESSIBLE so the Idira System
# connector can reach it for SRS rotation later.
#
# It deliberately does NOT vault the credential — the student does that in the
# activity (Step E: expose -> vault -> secure -> rotate).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# --- Configuration (env-overridable) ----------------------------------------
DB_CONTAINER_NAME="${DB_CONTAINER_NAME:-activity-db}"
DB_IMAGE="${DB_IMAGE:-postgres:16-alpine}"
DB_NAME="${DB_NAME:-trainingdb}"

# Initial credential: what the hardcoded script uses and what the student vaults.
# NOT a secret to protect — it is intentionally exposed in the hardcoded script.
DB_INITIAL_USER="${DB_INITIAL_USER:-appuser}"
DB_INITIAL_PASSWORD="${DB_INITIAL_PASSWORD:-InitialSecret1!}"

# Networking: publish so the Idira System connector can reach 5432. Restrict the
# port to the connector at the VM firewall / NSG / SIA-network layer (see notes
# printed at the end). Bind to all interfaces by default; override to the VM
# private IP for a tighter bind.
DB_BIND_ADDR="${DB_BIND_ADDR:-0.0.0.0}"
DB_PORT="${DB_PORT:-5432}"

# Optional: connector source CIDR, used only to print firewall guidance.
CONNECTOR_CIDR="${CONNECTOR_CIDR:-}"

DROP_EXISTING="${DROP_EXISTING:-false}"
INSTALL_DOCKER_SCRIPT="${INSTALL_DOCKER_SCRIPT:-$REPO_ROOT/compute_init/ubuntu/install_docker.sh}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Stands up the VM-local Postgres for the Summon Azure Auth activity: an initial
credential (later vaulted by the student), the seeded demo table, and a
port-accessible listener for SRS rotation via the Idira System connector.

Options:
  --name NAME          Container name. Default: ${DB_CONTAINER_NAME}
  --db NAME            Database name. Default: ${DB_NAME}
  --user NAME          Initial DB user (student vaults this). Default: ${DB_INITIAL_USER}
  --password VALUE     Initial DB password. Default: (built-in demo value)
  --bind ADDR          Publish bind address. Default: ${DB_BIND_ADDR}
  --port PORT          Published port. Default: ${DB_PORT}
  --connector-cidr CIDR  Connector source range (for firewall guidance only).
  --drop-existing      Recreate the container and its data.
  -h, --help           Show this help.

Environment overrides: DB_CONTAINER_NAME, DB_IMAGE, DB_NAME, DB_INITIAL_USER,
DB_INITIAL_PASSWORD, DB_BIND_ADDR, DB_PORT, CONNECTOR_CIDR, DROP_EXISTING,
INSTALL_DOCKER_SCRIPT
EOF
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) DB_CONTAINER_NAME="$2"; shift 2 ;;
    --db) DB_NAME="$2"; shift 2 ;;
    --user) DB_INITIAL_USER="$2"; shift 2 ;;
    --password) DB_INITIAL_PASSWORD="$2"; shift 2 ;;
    --bind) DB_BIND_ADDR="$2"; shift 2 ;;
    --port) DB_PORT="$2"; shift 2 ;;
    --connector-cidr) CONNECTOR_CIDR="$2"; shift 2 ;;
    --drop-existing) DROP_EXISTING=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# --- Docker (rootful; usable by the setup user) ------------------------------
docker_cmd=(docker)
ensure_docker() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    docker_cmd=(sudo docker)
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    if [[ -x "$INSTALL_DOCKER_SCRIPT" ]]; then
      echo "Docker not found; running installer: $INSTALL_DOCKER_SCRIPT"
      "$INSTALL_DOCKER_SCRIPT"
    else
      echo "ERROR: Docker is not installed and installer not found: $INSTALL_DOCKER_SCRIPT" >&2
      exit 1
    fi
  fi
  if docker info >/dev/null 2>&1; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    docker_cmd=(sudo docker)
    return 0
  fi
  echo "ERROR: Docker is installed but not usable by this user (try re-login for the docker group, or run with sudo)." >&2
  exit 1
}

dk() { "${docker_cmd[@]}" "$@"; }

container_exists() { dk inspect "$DB_CONTAINER_NAME" >/dev/null 2>&1; }
container_running() { [[ "$(dk inspect -f '{{.State.Running}}' "$DB_CONTAINER_NAME" 2>/dev/null || echo false)" == "true" ]]; }

ensure_docker

if is_true "$DROP_EXISTING" && container_exists; then
  echo "Removing existing container: $DB_CONTAINER_NAME"
  dk rm -f "$DB_CONTAINER_NAME" >/dev/null
fi

if container_exists; then
  if ! container_running; then
    echo "Starting existing container: $DB_CONTAINER_NAME"
    dk start "$DB_CONTAINER_NAME" >/dev/null
  else
    echo "Container already running: $DB_CONTAINER_NAME (use --drop-existing to recreate)"
  fi
else
  echo "Starting Postgres container: $DB_CONTAINER_NAME (${DB_IMAGE})"
  echo "  publish: ${DB_BIND_ADDR}:${DB_PORT} -> 5432  |  db: ${DB_NAME}  user: ${DB_INITIAL_USER}"
  dk run --detach \
    --name "$DB_CONTAINER_NAME" \
    --restart unless-stopped \
    --publish "${DB_BIND_ADDR}:${DB_PORT}:5432" \
    --env "POSTGRES_DB=${DB_NAME}" \
    --env "POSTGRES_USER=${DB_INITIAL_USER}" \
    --env "POSTGRES_PASSWORD=${DB_INITIAL_PASSWORD}" \
    "$DB_IMAGE" >/dev/null
fi

# --- Wait for readiness ------------------------------------------------------
echo -n "Waiting for Postgres to accept connections"
for _ in $(seq 1 30); do
  if dk exec "$DB_CONTAINER_NAME" pg_isready -U "$DB_INITIAL_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    ready=true
    break
  fi
  echo -n "."
  sleep 1
done
echo
if [[ "${ready:-false}" != "true" ]]; then
  echo "ERROR: Postgres did not become ready in time." >&2
  dk logs --tail 40 "$DB_CONTAINER_NAME" >&2 || true
  exit 1
fi

# --- Seed the demo table (idempotent) ----------------------------------------
echo "Seeding ${DB_NAME}.public.example_table"
dk exec -i \
  --env "PGPASSWORD=${DB_INITIAL_PASSWORD}" \
  "$DB_CONTAINER_NAME" \
  psql -v ON_ERROR_STOP=1 -U "$DB_INITIAL_USER" -d "$DB_NAME" >/dev/null <<'SQL'
CREATE TABLE IF NOT EXISTS example_table (
    id             SERIAL PRIMARY KEY,
    series_title   TEXT NOT NULL,
    primary_setting TEXT NOT NULL,
    lead_character TEXT NOT NULL,
    story_hook     TEXT NOT NULL
);

INSERT INTO example_table (series_title, primary_setting, lead_character, story_hook)
SELECT v.series_title, v.primary_setting, v.lead_character, v.story_hook
FROM (VALUES
    ('Star Trek: The Next Generation', 'USS Enterprise', 'Jean Luc', 'First contact'),
    ('Star Trek: Voyager', 'USS Voyager', 'Kathryn Janeway', 'Return voyage'),
    ('Star Trek: Deep Space Nine', 'Station Nine', 'Benjamin Sisko', 'Wormhole defense'),
    ('Battlestar Galactica', 'Battlestar Galactica', 'William Adama', 'Fleet survival'),
    ('The Expanse', 'Rocinante', 'James Holden', 'Political crisis'),
    ('Doctor Who', 'TARDIS', 'The Doctor', 'Time travel'),
    ('Babylon 5', 'Babylon Station', 'John Sheridan', 'Alien diplomacy'),
    ('Firefly', 'Serenity', 'Malcolm Reynolds', 'Cargo jobs'),
    ('Stargate SG-1', 'Stargate Command', 'Jack ONeill', 'Gate missions'),
    ('Stargate Atlantis', 'Atlantis City', 'John Sheppard', 'Ancient tech'),
    ('Farscape', 'Moya', 'John Crichton', 'Lost astronaut'),
    ('Andor', 'Imperial Galaxy', 'Cassian Andor', 'Rebel origins'),
    ('The Mandalorian', 'Outer Rim', 'Din Djarin', 'Bounty code'),
    ('Lost in Space', 'Jupiter Two', 'Maureen Robinson', 'Family survival'),
    ('Foundation', 'Trantor Empire', 'Hari Seldon', 'Future math'),
    ('Dark Matter', 'Raza', 'Android Crew', 'Memory loss'),
    ('Killjoys', 'Lucy Ship', 'Dutch', 'Warrant hunters'),
    ('The Orville', 'USS Orville', 'Ed Mercer', 'Planetary survey'),
    ('Red Dwarf', 'Red Dwarf', 'Dave Lister', 'Last human'),
    ('Space: 1999', 'Lunar Base', 'John Koenig', 'Moon exile')
) AS v(series_title, primary_setting, lead_character, story_hook)
WHERE NOT EXISTS (SELECT 1 FROM example_table);
SQL

row_count="$(dk exec \
  --env "PGPASSWORD=${DB_INITIAL_PASSWORD}" \
  "$DB_CONTAINER_NAME" \
  psql -tA -U "$DB_INITIAL_USER" -d "$DB_NAME" -c 'SELECT count(*) FROM example_table;' 2>/dev/null | tr -d '[:space:]')"

echo
echo "Local Postgres is ready."
echo "  container : ${DB_CONTAINER_NAME} (${DB_IMAGE})"
echo "  database  : ${DB_NAME}"
echo "  table     : public.example_table (${row_count:-?} rows)"
echo "  listener  : ${DB_BIND_ADDR}:${DB_PORT}"
echo "  initial   : user=${DB_INITIAL_USER} password=${DB_INITIAL_PASSWORD}  (exposed in the hardcoded script; student vaults this)"
echo
echo "Rotation readiness (SRS via the Idira System connector):"
echo "  - The initial user is the container superuser, so it can rotate its own"
echo "    password (ALTER ROLE). Use a reconcile account instead if required."
echo "  - Postgres is published on ${DB_PORT}; open ${DB_PORT} to the connector ONLY:"
if [[ -n "$CONNECTOR_CIDR" ]]; then
  echo "      e.g. allow ${CONNECTOR_CIDR} -> tcp/${DB_PORT} at the VM firewall / NSG / SIA network"
else
  echo "      restrict tcp/${DB_PORT} to the connector's source range at the VM firewall / NSG / SIA network"
  echo "      (pass --connector-cidr <CIDR> to print an explicit rule)"
fi
echo "  - The official image's pg_hba allows host password auth (scram) when a"
echo "    password is set; tighten pg_hba to the connector range if needed."
