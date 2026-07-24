#!/bin/bash
# Deployment enablement for the Summon Azure Auth workshop.
#
# This runs at VM provisioning (control plane), NOT by the student. It:
#   1. installs Summon + the summon-conjur provider,
#   2. validates that a PostgreSQL credential platform is active on the tenant,
#   3. provisions authn-azure + the workload identity (Conjur), and
#   4. renders the Summon secrets map.
#
# It intentionally does NOT create the safe or vault the DB credential — the
# student does that in the activity (expose -> vault -> secure -> rotate). The
# workload->safe consumers grant is applied later by setup/conjur/grant_consumers.sh
# once the student has created the safe and it has synced into Conjur.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

if [ -f /etc/profile.d/cyberark.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

printf "==========================================\n"
printf "Setup: Summon Azure Auth (deployment enablement)\n"
printf "==========================================\n\n"
printf "Sets up authn-azure + the workload identity, validates the Postgres\n"
printf "platform on the tenant, and renders the Summon secrets map. It does NOT\n"
printf "create the safe or vault the DB credential; the student does that in the\n"
printf "activity.\n\n"

INSTALL_SCRIPT="$SCRIPT_DIR/../../../compute_init/ubuntu/install_summon.sh"
CONJUR_SETUP_SCRIPT="$SCRIPT_DIR/setup/conjur/setup.sh"
SECRETS_TEMPLATE="$SCRIPT_DIR/secrets.tmpl.yml"
SECRETS_RESOLVED="$SCRIPT_DIR/secrets.yml"

render_secrets_file() {
  local template_file="$1"
  local output_file="$2"

  if [ ! -f "$template_file" ]; then
    printf "ERROR: Secrets template not found: %s\n" "$template_file" >&2
    exit 1
  fi

  if [ -z "${SAFE_NAME:-}" ]; then
    printf "ERROR: SAFE_NAME is required to render the secrets file\n" >&2
    exit 1
  fi

  sed "s|{{ SAFE_NAME }}|$SAFE_NAME|g" "$template_file" > "$output_file"
}

if [ ! -f "$INSTALL_SCRIPT" ]; then
  printf "ERROR: Shared install script not found: %s\n" "$INSTALL_SCRIPT" >&2
  exit 1
fi

if [ ! -x "$CONJUR_SETUP_SCRIPT" ]; then
  printf "ERROR: Conjur setup script not found or not executable: %s\n" "$CONJUR_SETUP_SCRIPT" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/setup/vars.env" ]; then
  printf "ERROR: Demo vars file not found: %s\n" "$SCRIPT_DIR/setup/vars.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup/vars.env"
set +a

printf "[1/4] Installing Summon and summon-conjur provider...\n"
bash "$INSTALL_SCRIPT"

printf "\n[2/4] Validating the Postgres credential platform on the tenant...\n"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to authenticate to Identity for platform validation.\n" >&2
  exit 1
fi
if postgres_platform_available "$TENANT_SUBDOMAIN" "$identity_token"; then
  printf "OK: an active PostgreSQL credential platform is available on %s.\n" "$TENANT_SUBDOMAIN"
  printf "    Rotation note: the platform's connection command must use the installed ODBC\n"
  printf "    driver name, e.g. Driver={PostgreSQL Unicode};Server=%%ADDRESS%%;[Database=%%DATABASE%%;]Uid=%%USER%%;Pwd=%%LOGONPASSWORD%%;[Port=%%PORT%%]\n"
  printf "    A driver-name mismatch causes SRS rotation to fail with IM002 (see demo_setup.md).\n"
else
  printf "ERROR: No active PostgreSQL credential platform found on the tenant (%s).\n" "$TENANT_SUBDOMAIN" >&2
  printf "Import and activate a PostgreSQL platform in Privilege Cloud before running the\n" >&2
  printf "workshop: the student needs it to onboard the DB account and SRS needs it to\n" >&2
  printf "rotate the credential. (Override the match keyword via POSTGRES_PLATFORM_ID.)\n" >&2
  exit 1
fi

printf "\n[3/4] Provisioning Azure authenticator, workload identity, and runtime environment...\n"
"$CONJUR_SETUP_SCRIPT"

printf "\n[4/4] Rendering resolved Summon secrets file...\n"
render_secrets_file "$SECRETS_TEMPLATE" "$SECRETS_RESOLVED"

printf "\nDeployment enablement completed.\n\n"
printf "The safe is NOT created here. In the activity, the student (signed in to idira):\n"
printf "  1. creates the safe named '%s' and vaults the DB credential,\n" "${SAFE_NAME:-<vm-name>}"
printf "  2. (control plane) run: setup/conjur/grant_consumers.sh   # after the safe syncs\n"
printf "  3. source ./conjur_authn_azure.env  &&  ./run_secured_query.sh\n"
