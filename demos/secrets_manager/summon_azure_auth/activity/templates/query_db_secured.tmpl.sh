#!/bin/bash
set -euo pipefail

# SECURED: no credentials in this script. PGUSER and PGPASSWORD are injected at
# runtime by Summon from CyberArk Secrets Manager (see run_secured_query.sh and
# secrets.yml). Only non-secret connection details are set here.
export PGHOST=__DB_HOST__
export PGPORT=__DB_PORT__
export PGDATABASE=__DB_NAME__

# This script carries no credentials of its own — Summon injects PGUSER/PGPASSWORD
# at runtime. If they are missing, it was run directly instead of via Summon.
if [ -z "${PGUSER:-}" ] || [ -z "${PGPASSWORD:-}" ]; then
  echo "This is the SECURED query — it has no credentials of its own." >&2
  echo "Run it through Summon instead:  ./run_secured_query.sh" >&2
  echo "(Summon authenticates with the VM's managed identity and injects" >&2
  echo " PGUSER/PGPASSWORD from Idira Secrets Manager at runtime.)" >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 -c __SQL_QUERY_Q__
