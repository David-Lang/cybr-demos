#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/github.com"
# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
source "$demo_path/setup/vars.env"
set +a

# Validate required demo inputs early so a run fails fast with a clear message.
if [ -z "${JWT_CLAIM_IDENTITY:-}" ] || [ "${JWT_CLAIM_IDENTITY#*INPUT_REQUIRED}" != "$JWT_CLAIM_IDENTITY" ]; then
  printf 'ERROR: JWT_CLAIM_IDENTITY must be set to the GitHub actor value (in vars.env or the environment).\n' >&2
  exit 1
fi
if [ -z "${GH_REPO:-}" ] || [ "${GH_REPO#*INPUT_REQUIRED}" != "$GH_REPO" ]; then
  printf 'ERROR: GH_REPO must be set to the target owner/repo (in vars.env or the environment).\n' >&2
  exit 1
fi

# ISP Setup (ensure the service user has the Conjur Cloud Admin role)
cd "$demo_path/setup/isp"
./setup.sh

# Vault Setup
cd "$demo_path/setup/vault"
./setup.sh

# Conjur Setup
cd "$demo_path/setup/conjur"
./setup.sh

# Github Setup
cd "$demo_path/setup/github"
./setup.sh

# Validation (bootstrap + validate live in setup)
cd "$demo_path/setup"
./validate.sh
