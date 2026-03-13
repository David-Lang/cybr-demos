#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/setup/vars.env"
export DEMO_NAMESPACE="${SM_SERVICE_NAME:-default}"

echo "Rancher deploy path, standard Kubernetes validation patterns"
echo "Namespace: $DEMO_NAMESPACE"
echo "Suggested first checks:"
echo "  kubectl get all -n \"$DEMO_NAMESPACE\""
echo "  kubectl get secretstore,externalsecret -n \"$DEMO_NAMESPACE\""
echo "  kubectl get pods -n external-secrets"
echo
echo "press any key to enter k9s"
read -rsn1

k9s
