#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LABS_ROOT="${LABS_ROOT:-/opt/labs}"
ACTIVITY_DIR_NAME="${ACTIVITY_DIR_NAME:-hardcoded-secret-remediation}"
STUDENT_PREFIX="${STUDENT_PREFIX:-student}"
STUDENT_COUNT="${STUDENT_COUNT:-30}"
CONJUR_AUTHN_AZURE_ENV="${CONJUR_AUTHN_AZURE_ENV:-$DEMO_DIR/conjur_authn_azure.env}"

SQL_QUERY="${SQL_QUERY:-SELECT TOP 5 * FROM dbo.ExampleTable}"
DB_USERNAME_TEMPLATE="${DB_USERNAME_TEMPLATE:-${DB_USERNAME:-__STUDENT___user}}"
DB_PASSWORD_TEMPLATE="${DB_PASSWORD_TEMPLATE:-${DB_PASSWORD:-}}"
SAFE_NAME_TEMPLATE="${SAFE_NAME_TEMPLATE:-${LAB_ID:-lab}-__STUDENT__-sql}"
ACCOUNT_NAME_TEMPLATE="${ACCOUNT_NAME_TEMPLATE:-azure-sql-__STUDENT__}"

require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    printf "ERROR: Required environment variable is not set: %s\n" "$var_name" >&2
    exit 1
  fi
}

shell_quote() {
  printf "%q" "$1"
}

render_string() {
  local value="$1"
  local token_student="__STUDENT__"
  local token_n="__N__"
  local token_nn="__NN__"

  value="${value//$token_student/$STUDENT}"
  value="${value//$token_nn/$NN}"
  value="${value//$token_n/$N}"
  printf "%s" "$value"
}

student_value() {
  local override_prefix="$1"
  local template_value="$2"
  local override_name="${override_prefix}_${N}"
  local override_value="${!override_name:-}"

  if [ -n "$override_value" ]; then
    printf "%s" "$override_value"
  else
    render_string "$template_value"
  fi
}

render_file() {
  local input_file="$1"
  local output_file="$2"
  local line rendered
  local token_student="__STUDENT__"
  local token_n="__N__"
  local token_nn="__NN__"
  local token_sql_server="__SQL_SERVER__"
  local token_sql_database="__SQL_DATABASE__"
  local token_db_username="__DB_USERNAME__"
  local token_db_password="__DB_PASSWORD__"
  local token_safe_name="__SAFE_NAME__"
  local token_account_name="__ACCOUNT_NAME__"
  local token_sql_query="__SQL_QUERY__"
  local token_sql_server_q="__SQL_SERVER_Q__"
  local token_sql_database_q="__SQL_DATABASE_Q__"
  local token_db_username_q="__DB_USERNAME_Q__"
  local token_db_password_q="__DB_PASSWORD_Q__"
  local token_sql_query_q="__SQL_QUERY_Q__"

  : > "$output_file"
  while IFS= read -r line || [ -n "$line" ]; do
    rendered="$line"
    rendered="${rendered//$token_sql_server_q/$SQL_SERVER_Q}"
    rendered="${rendered//$token_sql_database_q/$SQL_DATABASE_Q}"
    rendered="${rendered//$token_db_username_q/$DB_USERNAME_Q}"
    rendered="${rendered//$token_db_password_q/$DB_PASSWORD_Q}"
    rendered="${rendered//$token_sql_query_q/$SQL_QUERY_Q}"
    rendered="${rendered//$token_sql_server/$SQL_SERVER_VALUE}"
    rendered="${rendered//$token_sql_database/$SQL_DATABASE_VALUE}"
    rendered="${rendered//$token_db_username/$DB_USERNAME_VALUE}"
    rendered="${rendered//$token_db_password/$DB_PASSWORD_VALUE}"
    rendered="${rendered//$token_safe_name/$SAFE_NAME_VALUE}"
    rendered="${rendered//$token_account_name/$ACCOUNT_NAME_VALUE}"
    rendered="${rendered//$token_sql_query/$SQL_QUERY_VALUE}"
    rendered="${rendered//$token_student/$STUDENT}"
    rendered="${rendered//$token_nn/$NN}"
    rendered="${rendered//$token_n/$N}"
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

require_env "SQL_SERVER"
require_env "SQL_DATABASE"

if [ ! -f "$CONJUR_AUTHN_AZURE_ENV" ]; then
  printf "ERROR: Azure runtime env file not found: %s\n" "$CONJUR_AUTHN_AZURE_ENV" >&2
  printf "Run the parent summon_azure_auth setup first or set CONJUR_AUTHN_AZURE_ENV.\n" >&2
  exit 1
fi

if ! [[ "$STUDENT_COUNT" =~ ^[0-9]+$ ]] || [ "$STUDENT_COUNT" -lt 1 ]; then
  printf "ERROR: STUDENT_COUNT must be a positive integer\n" >&2
  exit 1
fi

ensure_labs_root
copy_shared_assets

for ((N = 1; N <= STUDENT_COUNT; N++)); do
  printf -v NN "%02d" "$N"
  STUDENT="${STUDENT_PREFIX}${N}"

  SQL_SERVER_VALUE="$(student_value "SQL_SERVER" "$SQL_SERVER")"
  SQL_DATABASE_VALUE="$(student_value "SQL_DATABASE" "$SQL_DATABASE")"
  DB_USERNAME_VALUE="$(student_value "DB_USERNAME" "$DB_USERNAME_TEMPLATE")"
  DB_PASSWORD_VALUE="$(student_value "DB_PASSWORD" "$DB_PASSWORD_TEMPLATE")"
  SAFE_NAME_VALUE="$(student_value "SAFE_NAME" "$SAFE_NAME_TEMPLATE")"
  ACCOUNT_NAME_VALUE="$(student_value "ACCOUNT_NAME" "$ACCOUNT_NAME_TEMPLATE")"
  SQL_QUERY_VALUE="$(render_string "$SQL_QUERY")"

  if [ -z "$DB_PASSWORD_VALUE" ]; then
    printf "ERROR: Missing password for %s. Set DB_PASSWORD_TEMPLATE, DB_PASSWORD, or DB_PASSWORD_%s.\n" "$STUDENT" "$N" >&2
    exit 1
  fi

  SQL_SERVER_Q="$(shell_quote "$SQL_SERVER_VALUE")"
  SQL_DATABASE_Q="$(shell_quote "$SQL_DATABASE_VALUE")"
  DB_USERNAME_Q="$(shell_quote "$DB_USERNAME_VALUE")"
  DB_PASSWORD_Q="$(shell_quote "$DB_PASSWORD_VALUE")"
  SQL_QUERY_Q="$(shell_quote "$SQL_QUERY_VALUE")"

  student_dir="$LABS_ROOT/$STUDENT/$ACTIVITY_DIR_NAME"
  mkdir -p "$student_dir"

  render_file "$TEMPLATE_DIR/README.md.tmpl" "$student_dir/README.md"
  render_file "$TEMPLATE_DIR/student_guide.md.tmpl" "$student_dir/student_guide.md"
  render_file "$TEMPLATE_DIR/query_db_hardcoded.sh.tmpl" "$student_dir/query_db_hardcoded.sh"
  render_file "$TEMPLATE_DIR/query_db_secured.sh.tmpl" "$student_dir/query_db_secured.sh"
  render_file "$TEMPLATE_DIR/run_secured_query.sh.tmpl" "$student_dir/run_secured_query.sh"
  render_file "$TEMPLATE_DIR/secrets.yml.tmpl" "$student_dir/secrets.yml"

  ln -sfn "$LABS_ROOT/shared/conjur_authn_azure.env" "$student_dir/conjur_authn_azure.env"
  chmod +x "$student_dir/query_db_hardcoded.sh" "$student_dir/query_db_secured.sh" "$student_dir/run_secured_query.sh"
done

chmod -R a+rwX "$LABS_ROOT"

printf "Created %s student activity workspaces under %s\n" "$STUDENT_COUNT" "$LABS_ROOT"
printf "Example: %s/%s1/%s\n" "$LABS_ROOT" "$STUDENT_PREFIX" "$ACTIVITY_DIR_NAME"
