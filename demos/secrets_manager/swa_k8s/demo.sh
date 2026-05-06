#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
source "$SCRIPT_DIR/setup/vars.env"

NS_HARDCODED="${NAMESPACE_HARDCODED:-$LAB_ID-giftapp-hardcoded}"
NS_SWA="${NAMESPACE_SWA:-$LAB_ID-giftapp-swa}"
SWA_NS="${SWA_NAMESPACE:-swa-system}"

echo "=== SWA Kubernetes Demo ==="
echo
echo "Namespaces:"
echo "  SWA system:      $SWA_NS"
echo "  Attack app:      $NS_HARDCODED"
echo "  Defended app:    $NS_SWA"
echo
echo "Suggested demo flow:"
echo
echo "1) Show attack surface — secrets visible in pod:"
echo "   kubectl exec -n $NS_HARDCODED deploy/giftapp-hardcoded -- cat /etc/secrets/GIFTAPP_API_KEY"
echo "   kubectl exec -n $NS_HARDCODED deploy/giftapp-hardcoded -- cat /etc/secrets/DB_PASS"
echo "   kubectl get secret giftapp-hardcoded-secrets -n $NS_HARDCODED -o jsonpath='{.data}' | base64 -d"
echo
echo "2) Show SWA infrastructure:"
echo "   kubectl get pods -n $SWA_NS"
echo "   kubectl get daemonset swa-agent -n $SWA_NS"
echo
echo "3) Show giftapp-swa has no secret files:"
echo "   kubectl exec -n $NS_SWA deploy/giftapp-swa -- ls /etc/secrets/"
echo "   kubectl get configmap giftapp-swa-config -n $NS_SWA -o yaml"
echo
echo "4) Show SPIFFE socket mounted in giftapp-swa:"
echo "   kubectl exec -n $NS_SWA deploy/giftapp-swa -- ls -l /tmp/swa-agent/public/api.sock"
echo
echo "5) Show both apps serving traffic (check logs):"
echo "   kubectl logs -n $NS_HARDCODED deploy/giftapp-hardcoded --tail=20"
echo "   kubectl logs -n $NS_SWA deploy/giftapp-swa --tail=20"
echo
echo "Press any key to enter k9s"
read -rsn1

k9s
