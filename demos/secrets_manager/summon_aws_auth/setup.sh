#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

printf "==========================================\n"
printf "Setup: Summon AWS Auth\n"
printf "==========================================\n\n"

INSTALL_SCRIPT="$SCRIPT_DIR/../../../compute_init/ubuntu/install_summon.sh"
VAULT_SETUP_SCRIPT="$SCRIPT_DIR/setup/vault/setup.sh"
CONJUR_SETUP_SCRIPT="$SCRIPT_DIR/setup/conjur/setup.sh"

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

printf "[1/3] Installing Summon and summon-conjur provider...\n"
bash "$INSTALL_SCRIPT"

printf "\n[2/3] Provisioning demo safe and sample account...\n"
"$VAULT_SETUP_SCRIPT"

printf "\n[3/3] Provisioning Conjur workload and runtime environment...\n"
"$CONJUR_SETUP_SCRIPT"

printf "\nSetup completed successfully.\n\n"
printf "Next step:\n"
printf "   source ./conjur_authn_iam.env\n"
