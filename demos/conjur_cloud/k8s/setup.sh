#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/conjur_cloud/k8s_eks"
# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using ‘+’ rather than ‘-’ causes the option to be turned off
set -a
source "$demo_path/setup/vars.env"
set +a

sm_fqdn="$SM_FQDN"
sm_namespace="$NAMESPACE"

# Collect K8s metadata
cd "$demo_path/setup"
./discover_k8s.sh

# Setup Vault
cd "$demo_path/setup/vault"
./setup.sh

# Setup Secrets Manager
cd "$demo_path/setup/sm"
./setup.sh

# Setup K8s
cd "$demo_path/setup/k8s"
./setup.sh
