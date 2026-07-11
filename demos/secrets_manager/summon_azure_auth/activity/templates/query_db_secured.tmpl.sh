#!/bin/bash
set -euo pipefail

# SECURED: no credentials in this script. PGUSER and PGPASSWORD are injected at
# runtime by Summon from CyberArk Secrets Manager (see run_secured_query.sh and
# secrets.yml). Only non-secret connection details are set here.
export PGHOST=__DB_HOST__
export PGPORT=__DB_PORT__
export PGDATABASE=__DB_NAME__

: "${PGUSER:?PGUSER was not provided by Summon}"
: "${PGPASSWORD:?PGPASSWORD was not provided by Summon}"

psql -v ON_ERROR_STOP=1 -c __SQL_QUERY_Q__
