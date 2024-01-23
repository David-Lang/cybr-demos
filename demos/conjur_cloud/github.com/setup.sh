#!/bin/bash
set -euo pipefail

# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
source "setup/vars.env"
set +a


# Vault Setup
cd setup/vault
./setup.sh

# Conjur Setup
cd ../../setup/conjur
./setup.sh
