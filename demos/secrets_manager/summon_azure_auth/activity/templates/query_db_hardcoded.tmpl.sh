#!/bin/bash
set -euo pipefail

# ANTI-PATTERN: the database password is hardcoded in this script.
# Anyone who can read this file can read the database.
export PGHOST=__DB_HOST__
export PGPORT=__DB_PORT__
export PGDATABASE=__DB_NAME__
export PGUSER=__DB_USERNAME__
export PGPASSWORD=__DB_PASSWORD_Q__

psql -v ON_ERROR_STOP=1 -c __SQL_QUERY_Q__
