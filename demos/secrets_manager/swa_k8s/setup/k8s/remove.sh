#!/bin/bash
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/swa_k8s"
set -a
source "$demo_path/setup/vars.env"
set +a

printf "\nUninstalling giftapp-hardcoded and mysql-hardcoded\n"
helm uninstall giftapp-hardcoded -n "$NAMESPACE_HARDCODED" 2>/dev/null || true
helm uninstall mysql-hardcoded   -n "$NAMESPACE_HARDCODED" 2>/dev/null || true
kubectl delete namespace "$NAMESPACE_HARDCODED" --ignore-not-found

printf "\nUninstalling giftapp-swa and mysql-swa\n"
helm uninstall giftapp-swa -n "$NAMESPACE_SWA" 2>/dev/null || true
helm uninstall mysql-swa   -n "$NAMESPACE_SWA" 2>/dev/null || true
kubectl delete namespace "$NAMESPACE_SWA" --ignore-not-found

printf "\nApp namespaces removed\n"
