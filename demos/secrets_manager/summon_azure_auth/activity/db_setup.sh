#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

KEYVAULT_NAME="${KEYVAULT_NAME:-}"
SECRET_NAME="${SECRET_NAME:-db-credentials}"
SQL_SERVER="${SQL_SERVER:-}"
SQL_DATABASE="${SQL_DATABASE:-}"
SQL_USERNAME="${SQL_USERNAME:-}"
SQL_PASSWORD="${SQL_PASSWORD:-}"
SQLCMD_BIN="${SQLCMD_BIN:-sqlcmd}"
INSTALL_SQLCMD_SCRIPT="${INSTALL_SQLCMD_SCRIPT:-$REPO_ROOT/compute_init/ubuntu/install_sqlcmd.sh}"
DROP_EXISTING="${DROP_EXISTING:-false}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Creates dbo.ExampleTable and inserts 20 sci-fi TV themed rows.

Connection options:
  --keyvault NAME      Read connection details from Key Vault secret.
                       Default secret name: db-credentials.
  --secret NAME        Secret name to read with --keyvault. Default: db-credentials.
  --server HOST        SQL Server host, such as example.database.windows.net.
  --database NAME      SQL database name.
  --username NAME      SQL username.
  --password VALUE     SQL password.

Other options:
  --drop-existing      Drop dbo.ExampleTable before creating it.
  -h, --help           Show this help.

Environment:
  KEYVAULT_NAME, SECRET_NAME, SQL_SERVER, SQL_DATABASE, SQL_USERNAME,
  SQL_PASSWORD, SQLCMD_BIN, INSTALL_SQLCMD_SCRIPT, DROP_EXISTING

Examples:
  ./db_setup.sh --keyvault lab-bca538-student1-kv
  SQL_SERVER=server.database.windows.net SQL_DATABASE=db SQL_USERNAME=user SQL_PASSWORD=pass ./db_setup.sh
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_nonempty() {
  local name="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "$name is required." >&2
    exit 1
  fi
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_sqlcmd() {
  local candidate

  if command -v "$SQLCMD_BIN" >/dev/null 2>&1; then
    command -v "$SQLCMD_BIN"
    return 0
  fi

  for candidate in /usr/local/bin/sqlcmd /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_sqlcmd() {
  if SQLCMD_PATH="$(resolve_sqlcmd)"; then
    return 0
  fi

  if [[ ! -x "$INSTALL_SQLCMD_SCRIPT" ]]; then
    echo "Missing required SQL client: $SQLCMD_BIN" >&2
    echo "SQL installer not found or not executable: $INSTALL_SQLCMD_SCRIPT" >&2
    echo "Set SQLCMD_BIN=/path/to/sqlcmd or INSTALL_SQLCMD_SCRIPT=/path/to/install_sqlcmd.sh." >&2
    exit 1
  fi

  echo "Missing SQL client: $SQLCMD_BIN"
  echo "Running SQL client installer: $INSTALL_SQLCMD_SCRIPT"
  "$INSTALL_SQLCMD_SCRIPT"

  if SQLCMD_PATH="$(resolve_sqlcmd)"; then
    return 0
  fi

  echo "SQL installer completed, but SQL client was not found: $SQLCMD_BIN" >&2
  echo "Set SQLCMD_BIN=/path/to/sqlcmd and rerun this script." >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keyvault)
      KEYVAULT_NAME="$2"
      shift 2
      ;;
    --secret)
      SECRET_NAME="$2"
      shift 2
      ;;
    --server)
      SQL_SERVER="$2"
      shift 2
      ;;
    --database)
      SQL_DATABASE="$2"
      shift 2
      ;;
    --username)
      SQL_USERNAME="$2"
      shift 2
      ;;
    --password)
      SQL_PASSWORD="$2"
      shift 2
      ;;
    --drop-existing)
      DROP_EXISTING=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$KEYVAULT_NAME" ]]; then
  require_cmd az
  require_cmd jq

  secret_value="$(az keyvault secret show \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --query value \
    -o tsv)"

  SQL_SERVER="${SQL_SERVER:-$(printf '%s' "$secret_value" | jq -r '.server // empty')}"
  SQL_DATABASE="${SQL_DATABASE:-$(printf '%s' "$secret_value" | jq -r '.database // empty')}"
  SQL_USERNAME="${SQL_USERNAME:-$(printf '%s' "$secret_value" | jq -r '.username // empty')}"
  SQL_PASSWORD="${SQL_PASSWORD:-$(printf '%s' "$secret_value" | jq -r '.password // empty')}"
fi

require_nonempty SQL_SERVER "$SQL_SERVER"
require_nonempty SQL_DATABASE "$SQL_DATABASE"
require_nonempty SQL_USERNAME "$SQL_USERNAME"
require_nonempty SQL_PASSWORD "$SQL_PASSWORD"
ensure_sqlcmd

drop_statement=""
if is_true "$DROP_EXISTING"; then
  drop_statement="DROP TABLE IF EXISTS dbo.ExampleTable;"
fi

sql_script="$(mktemp)"
trap 'rm -f "$sql_script"' EXIT

cat >"$sql_script" <<EOF
SET NOCOUNT ON;

${drop_statement}

IF OBJECT_ID(N'dbo.ExampleTable', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ExampleTable
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        SeriesTitle NVARCHAR(60) NOT NULL,
        PrimarySetting NVARCHAR(60) NOT NULL,
        LeadCharacter NVARCHAR(60) NOT NULL,
        StoryHook NVARCHAR(80) NOT NULL
    );
END;

IF NOT EXISTS (SELECT 1 FROM dbo.ExampleTable)
BEGIN
    INSERT INTO dbo.ExampleTable
        (SeriesTitle, PrimarySetting, LeadCharacter, StoryHook)
    VALUES
        ('Star Trek', 'USS Enterprise', 'Jean Luc', 'First contact'),
        ('Voyager', 'USS Voyager', 'Kathryn Janeway', 'Return voyage'),
        ('Deep Space', 'Station Nine', 'Benjamin Sisko', 'Wormhole defense'),
        ('Galactica', 'Battlestar Galactica', 'William Adama', 'Fleet survival'),
        ('The Expanse', 'Rocinante', 'James Holden', 'Political crisis'),
        ('Doctor Who', 'TARDIS', 'The Doctor', 'Time travel'),
        ('Babylon Five', 'Babylon Station', 'John Sheridan', 'Alien diplomacy'),
        ('Firefly', 'Serenity', 'Malcolm Reynolds', 'Cargo jobs'),
        ('Stargate SG1', 'Stargate Command', 'Jack ONeill', 'Gate missions'),
        ('Stargate Atlantis', 'Atlantis City', 'John Sheppard', 'Ancient tech'),
        ('Farscape', 'Moya', 'John Crichton', 'Lost astronaut'),
        ('Andor', 'Imperial Galaxy', 'Cassian Andor', 'Rebel origins'),
        ('Mandalorian', 'Outer Rim', 'Din Djarin', 'Bounty code'),
        ('Lost Space', 'Jupiter Two', 'Maureen Robinson', 'Family survival'),
        ('Foundation', 'Trantor Empire', 'Hari Seldon', 'Future math'),
        ('Dark Matter', 'Raza', 'Android Crew', 'Memory loss'),
        ('Killjoys', 'Lucy Ship', 'Dutch', 'Warrant hunters'),
        ('The Orville', 'USS Orville', 'Ed Mercer', 'Planetary survey'),
        ('Red Dwarf', 'Red Dwarf', 'Dave Lister', 'Last human'),
        ('Moonbase Alpha', 'Lunar Base', 'John Koenig', 'Moon exile');
END;

SELECT COUNT(*) AS ExampleTableRows FROM dbo.ExampleTable;
EOF

echo "Configuring dbo.ExampleTable on ${SQL_SERVER}/${SQL_DATABASE} as ${SQL_USERNAME}"
SQLCMDPASSWORD="$SQL_PASSWORD" "$SQLCMD_PATH" \
  -S "$SQL_SERVER" \
  -d "$SQL_DATABASE" \
  -U "$SQL_USERNAME" \
  -b \
  -l 30 \
  -N \
  -C \
  -i "$sql_script"
