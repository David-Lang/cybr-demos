#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# INSECURE baseline, paired with run_secured_query.sh for a side-by-side
# before/after. This runs the query with the password HARDCODED in
# query_db_hardcoded.sh -- no Summon, no vault; the secret lives in the script.
exec ./query_db_hardcoded.sh
