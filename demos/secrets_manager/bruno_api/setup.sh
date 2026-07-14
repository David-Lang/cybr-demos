#!/bin/bash
# shellcheck disable=SC2059
# Sets up the "ALM API Key Auth" Bruno collection demo:
#   - installs the Bruno CLI (bru) if needed
#   - clones the poc-sm-saas-bruno collection
#   - generates a git-ignored Bruno environment from the tenant service creds
#   - runs the Setup App section via `bru run` (showcases the Secrets Manager API)
#   - captures the workload API key (via the service/root token) into the env so the
#     Demo App (CLI or GUI) can authenticate as the workload
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/bruno_api"

# Inputs (env-overridable)
BRUNO_REPO="${BRUNO_REPO:-David-Lang/poc-sm-saas-bruno}"
BRUNO_BRANCH="${BRUNO_BRANCH:-main}"
APP_BASE="${UseCaseAlmAppName:-poc-alm-app}"
# Env name ends in ".secret" so the generated file (cybr.secret.bru) is:
#  - git-ignored by the collection's own .gitignore (*.secret.*), and
#  - obviously secret-bearing by name.
ENV_NAME="cybr.secret"

WORK_DIR="$demo_path/.collection"
COLLECTION_DIR="$WORK_DIR/collection"
ENV_FILE="$COLLECTION_DIR/environments/$ENV_NAME.bru"

main() {
  set_variables

  ensure_tool_installed bru

  clone_collection
  write_env_file
  run_setup_app
  capture_workload_api_key

  printf "\nSetup complete.\n"
  printf "  Collection: %s\n" "$COLLECTION_DIR"
  printf "  Bruno env:  %s (env name: %s)\n" "$ENV_FILE" "$ENV_NAME"
  printf "  App name:   %s\n" "$app_name"
  printf "Run the demo with: %s/demo.sh\n" "$demo_path"
}

# shellcheck disable=SC2153
set_variables() {
  : "${TENANT_ID:?TENANT_ID must be set}"
  : "${TENANT_SUBDOMAIN:?TENANT_SUBDOMAIN must be set}"
  : "${LAB_ID:?LAB_ID must be set (used to build a stable, idempotent app name)}"
  isp_id="$TENANT_ID"
  isp_subdomain="$TENANT_SUBDOMAIN"
  client_id="$CLIENT_ID"
  client_secret="$CLIENT_SECRET"
  # Stable app name derived from LAB_ID -> idempotent across runs.
  app_name="${APP_BASE}-${LAB_ID}"
}

clone_collection() {
  if [ -d "$COLLECTION_DIR" ]; then
    printf "\nRefreshing existing collection clone\n"
    git -C "$WORK_DIR" pull --ff-only 2>/dev/null || true
  else
    printf "\nCloning Bruno collection %s (branch %s)\n" "$BRUNO_REPO" "$BRUNO_BRANCH"
    gh repo clone "$BRUNO_REPO" "$WORK_DIR" -- -b "$BRUNO_BRANCH"
  fi
  [ -f "$COLLECTION_DIR/bruno.json" ] || {
    printf "ERROR: bruno.json not found under %s\n" "$COLLECTION_DIR" >&2
    exit 1
  }
}

# Generate a git-ignored Bruno environment from the service-account creds.
write_env_file() {
  printf "\nWriting Bruno environment %s\n" "$ENV_FILE"
  mkdir -p "$COLLECTION_DIR/environments"
  cat > "$ENV_FILE" <<EOF
vars {
  ConjurAccount: conjur
  UseCaseAlmAppName: ${app_name}
  LabId: ${LAB_ID}
  IspTenantId: ${isp_id}
  IspSubDomain: ${isp_subdomain}
  IspServiceClientId: ${client_id}
  IspServiceClientSecret: ${client_secret}
  identityToken:
  conjurSessionToken:
  almAppName_workload_ApiKey:
}
EOF
  chmod 600 "$ENV_FILE"
}

run_setup_app() {
  printf "\nRunning Bruno Setup App section (bru run)\n"
  ( cd "$COLLECTION_DIR" && bru run "Use Cases/ALM API Key Auth/1 Setup App" -r --env "$ENV_NAME" ) || {
    printf "NOTE: some Setup App steps may report errors on re-run (already-exists); continuing.\n"
  }
}

# Rotate + capture the workload API key using the service/root token, then persist
# it into the Bruno env so the Demo App can authenticate as the workload.
capture_workload_api_key() {
  printf "\nCapturing workload API key (via service token)\n"
  local workload="data/${app_name}/${app_name}-workload"
  local identity_token conjur_token api_key
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
  api_key=$(rotate_workload_api_key "$isp_subdomain" "$conjur_token" "$workload")
  # A Conjur API key is a long alphanumeric string; reject error bodies (JSON/HTML).
  if ! printf '%s' "$api_key" | grep -qE '^[A-Za-z0-9]{40,}$'; then
    printf "ERROR: did not get a valid workload API key for host:%s\n" "$workload" >&2
    printf "       (the Setup App may not have created the workload). Response:\n%s\n" "$api_key" >&2
    exit 1
  fi
  set_env_var "almAppName_workload_ApiKey" "$api_key"
}

# Set a var value inside the generated Bruno env file.
set_env_var() {
  local key="$1" value="$2"
  # Replace the "  key:" line (value may be empty or present).
  local tmp
  tmp="$(mktemp)"
  awk -v k="  $key:" -v v="  $key: $value" '
    { if (index($0, k) == 1) print v; else print $0 }
  ' "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
}

main "$@"
