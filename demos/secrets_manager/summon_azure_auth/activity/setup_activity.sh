#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INPUTS_ENV="${INPUTS_ENV:-$SCRIPT_DIR/inputs.env}"

if [ ! -f "$INPUTS_ENV" ]; then
  printf "ERROR: Activity inputs file not found: %s\n" "$INPUTS_ENV" >&2
  printf "Create or edit activity/inputs.env and set the required values.\n" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$INPUTS_ENV"
set +a

LABS_ROOT="${LABS_ROOT:-/opt/labs}"
ACTIVITY_DIR_NAME="${ACTIVITY_DIR_NAME:-hardcoded-secret-remediation}"
STUDENT_PREFIX="${STUDENT_PREFIX:-student}"
STUDENT_COUNT="${STUDENT_COUNT:-1}"
CONJUR_AUTHN_AZURE_ENV="${CONJUR_AUTHN_AZURE_ENV:-$DEMO_DIR/conjur_authn_azure.env}"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-trainingdb}"
DB_USERNAME="${DB_USERNAME:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-InitialSecret1!}"
SQL_QUERY="${SQL_QUERY:-SELECT * FROM example_table ORDER BY id LIMIT 5;}"
SAFE_NAME="${SAFE_NAME:-$(hostname -s 2>/dev/null || hostname)}"
ACCOUNT_NAME="${ACCOUNT_NAME:-postgres-appuser}"
ROTATION_ADDRESS="${ROTATION_ADDRESS:-$(hostname -f 2>/dev/null || hostname)}"

shell_quote() {
  printf "%q" "$1"
}

render_file() {
  local input_file="$1"
  local output_file="$2"
  local line rendered

  : > "$output_file"
  while IFS= read -r line || [ -n "$line" ]; do
    rendered="$line"
    rendered="${rendered//__SQL_QUERY_Q__/$SQL_QUERY_Q}"
    rendered="${rendered//__SQL_QUERY__/$SQL_QUERY}"
    rendered="${rendered//__DB_HOST__/$DB_HOST}"
    rendered="${rendered//__DB_PORT__/$DB_PORT}"
    rendered="${rendered//__DB_NAME__/$DB_NAME}"
    rendered="${rendered//__DB_USERNAME__/$DB_USERNAME}"
    rendered="${rendered//__DB_PASSWORD_Q__/$DB_PASSWORD_Q}"
    rendered="${rendered//__DB_PASSWORD__/$DB_PASSWORD}"
    rendered="${rendered//__ROTATION_ADDRESS__/$ROTATION_ADDRESS}"
    rendered="${rendered//__SAFE_NAME__/$SAFE_NAME}"
    rendered="${rendered//__ACCOUNT_NAME__/$ACCOUNT_NAME}"
    rendered="${rendered//__STUDENT__/$STUDENT}"
    rendered="${rendered//__NN__/$NN}"
    rendered="${rendered//__N__/$N}"
    printf "%s\n" "$rendered" >> "$output_file"
  done < "$input_file"
}

ensure_labs_root() {
  if [ ! -d "$LABS_ROOT" ]; then
    if ! mkdir -p "$LABS_ROOT" 2>/dev/null; then
      sudo mkdir -p "$LABS_ROOT"
    fi
  fi

  if [ ! -w "$LABS_ROOT" ]; then
    sudo chmod -R a+rwX "$LABS_ROOT"
  fi
}

copy_shared_assets() {
  local shared_dir="$LABS_ROOT/shared"
  local shared_templates="$shared_dir/templates"

  mkdir -p "$shared_templates"
  cp "$TEMPLATE_DIR"/* "$shared_templates"/
  cp "$CONJUR_AUTHN_AZURE_ENV" "$shared_dir/conjur_authn_azure.env"
  chmod -R a+rwX "$shared_dir"
}

if [ ! -f "$CONJUR_AUTHN_AZURE_ENV" ]; then
  printf "ERROR: Azure runtime env file not found: %s\n" "$CONJUR_AUTHN_AZURE_ENV" >&2
  printf "Run the parent summon_azure_auth setup first or set CONJUR_AUTHN_AZURE_ENV.\n" >&2
  exit 1
fi

if ! [[ "$STUDENT_COUNT" =~ ^[0-9]+$ ]] || [ "$STUDENT_COUNT" -lt 1 ]; then
  printf "ERROR: STUDENT_COUNT must be a positive integer\n" >&2
  exit 1
fi

SQL_QUERY_Q="$(shell_quote "$SQL_QUERY")"
DB_PASSWORD_Q="$(shell_quote "$DB_PASSWORD")"

ensure_labs_root
copy_shared_assets

for ((N = 1; N <= STUDENT_COUNT; N++)); do
  printf -v NN "%02d" "$N"
  STUDENT="${STUDENT_PREFIX}${N}"

  student_dir="$LABS_ROOT/$STUDENT/$ACTIVITY_DIR_NAME"
  mkdir -p "$student_dir"

  render_file "$TEMPLATE_DIR/README.tmpl.md" "$student_dir/README.md"
  render_file "$TEMPLATE_DIR/student_guide.tmpl.md" "$student_dir/student_guide.md"
  render_file "$TEMPLATE_DIR/query_db_hardcoded.tmpl.sh" "$student_dir/query_db_hardcoded.sh"
  render_file "$TEMPLATE_DIR/query_db_secured.tmpl.sh" "$student_dir/query_db_secured.sh"
  render_file "$TEMPLATE_DIR/run_secured_query.tmpl.sh" "$student_dir/run_secured_query.sh"
  render_file "$TEMPLATE_DIR/secrets.tmpl.yml" "$student_dir/secrets.yml"

  ln -sfn "$LABS_ROOT/shared/conjur_authn_azure.env" "$student_dir/conjur_authn_azure.env"
  chmod +x "$student_dir/query_db_hardcoded.sh" "$student_dir/query_db_secured.sh" "$student_dir/run_secured_query.sh"
done

chmod -R a+rwX "$LABS_ROOT"

printf "Created %s student activity workspace(s) under %s\n" "$STUDENT_COUNT" "$LABS_ROOT"
printf "Example: %s/%s1/%s\n" "$LABS_ROOT" "$STUDENT_PREFIX" "$ACTIVITY_DIR_NAME"
