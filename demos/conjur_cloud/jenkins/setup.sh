#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/conjur_cloud/jenkins"
# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
source "$demo_path/setup/vars.env"
set +a

# Vault Setup
cd "$demo_path/setup/vault" && ./setup.sh

# Conjur Setup
cd "$demo_path/setup/conjur" && ./setup.sh

# Vault Setup
cd "$demo_path/setup/jenkins" && ./setup.sh
