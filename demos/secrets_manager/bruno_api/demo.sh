#!/bin/bash
# shellcheck disable=SC2059
# Runs the "ALM API Key Auth" Demo App section via the Bruno CLI:
# authenticates as the application workload (using the captured workload API key)
# and retrieves secrets. Assumes setup.sh has already run.
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/bruno_api"
ENV_NAME="cybr.secret"
WORK_DIR="$demo_path/.collection"
COLLECTION_DIR="$WORK_DIR/collection"
ENV_FILE="$COLLECTION_DIR/environments/$ENV_NAME.bru"

main() {
  command -v bru >/dev/null 2>&1 || { printf "ERROR: bru CLI not found. Run setup.sh first.\n" >&2; exit 1; }
  [ -f "$COLLECTION_DIR/bruno.json" ] || { printf "ERROR: collection not found. Run setup.sh first.\n" >&2; exit 1; }
  [ -f "$ENV_FILE" ] || { printf "ERROR: Bruno env %s not found. Run setup.sh first.\n" "$ENV_FILE" >&2; exit 1; }

  if ! grep -qE '^\s*almAppName_workload_ApiKey:\s*\S' "$ENV_FILE"; then
    printf "ERROR: workload API key not present in %s. Re-run setup.sh.\n" "$ENV_FILE" >&2
    exit 1
  fi

  printf "\nRunning Bruno Demo App section (authenticate as workload -> retrieve secrets)\n"
  ( cd "$COLLECTION_DIR" && bru run "Use Cases/ALM API Key Auth/2 Demo App" -r --env "$ENV_NAME" )
}

main "$@"
