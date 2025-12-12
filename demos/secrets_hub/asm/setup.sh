#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_hub/aws_secrets_manager"
# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
source "$demo_path/setup/vars.env"
set +a

## AWS Setup
cd "$demo_path/setup/aws"
./setup.sh
#
## Conjur Setup
#cd "$demo_path/setup/conjur"
#./setup.sh
