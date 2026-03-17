#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f /etc/profile.d/cyberark.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

printf "==========================================\n"
printf "Setup: Summon AWS Auth\n"
printf "==========================================\n\n"

INSTALL_SCRIPT="$SCRIPT_DIR/../../../compute_init/ubuntu/install_summon.sh"
VAULT_SETUP_SCRIPT="$SCRIPT_DIR/setup/vault/setup.sh"
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

if [ ! -x "$VAULT_SETUP_SCRIPT" ]; then
  printf "ERROR: Vault setup script not found or not executable: %s\n" "$VAULT_SETUP_SCRIPT" >&2
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
source "$SCRIPT_DIR/setup/vars.env"
set +a

printf "[1/3] Installing Summon and summon-conjur provider...\n"
bash "$INSTALL_SCRIPT"

printf "\n[2/3] Provisioning demo safe and sample account...\n"
"$VAULT_SETUP_SCRIPT"

printf "\n[3/3] Provisioning Conjur workload and runtime environment...\n"
"$CONJUR_SETUP_SCRIPT"

printf "\nRendering resolved Summon secrets file...\n"
render_secrets_file "$SECRETS_TEMPLATE" "$SECRETS_RESOLVED"

printf "\nSetup completed successfully.\n\n"
printf "Next step:\n"
printf "   source ./conjur_authn_iam.env\n"
