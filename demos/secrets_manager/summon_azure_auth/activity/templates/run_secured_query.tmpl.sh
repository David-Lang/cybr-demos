#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# summon-conjur needs a home directory to locate its Conjur client config. The
# Azure run-command context (root, non-login shell) has no $HOME, which makes
# summon fail with "Failed to get user home directory: $HOME is not defined"
# BEFORE it ever calls Conjur (so nothing is audited). Default it so any
# non-login invocation works; a no-op for interactive SSH sessions.
export HOME="${HOME:-/root}"

if [ -f ./conjur_authn_azure.env ]; then
  # shellcheck disable=SC1091
  source ./conjur_authn_azure.env
fi

if ! command -v summon >/dev/null 2>&1; then
  echo "ERROR: summon is not installed" >&2
  exit 1
fi

if [ ! -f ./secrets.yml ]; then
  echo "ERROR: secrets.yml not found" >&2
  exit 1
fi

if [ ! -x ./query_db_secured.sh ]; then
  echo "ERROR: query_db_secured.sh is missing or not executable" >&2
  exit 1
fi

# Summon authenticates with the VM's Azure managed identity (authn-azure), reads
# secrets.yml, injects PGUSER/PGPASSWORD into the environment, and runs the
# secured query. No secret is stored on disk.
summon --provider summon-conjur -f ./secrets.yml ./query_db_secured.sh
