#!/bin/bash
# Cleanup: CyberArk Secrets Provider for K8s — sidecar mode
set -euo pipefail

NAMESPACE="sp-sidecar"

echo "[INFO] Removing Secrets Provider sidecar demo"

kubectl delete deployment -n "$NAMESPACE" sidecar-demo-app --ignore-not-found
kubectl delete secret -n "$NAMESPACE" db-credentials --ignore-not-found
kubectl delete configmap -n "$NAMESPACE" conjur-connect --ignore-not-found
kubectl delete sa -n "$NAMESPACE" sp-sidecar-sa --ignore-not-found
kubectl delete rolebinding -n "$NAMESPACE" secrets-access-binding --ignore-not-found
kubectl delete role -n "$NAMESPACE" secrets-access --ignore-not-found
kubectl delete ns "$NAMESPACE" --ignore-not-found

echo "[INFO] Cleanup complete"
echo "[NOTE] Conjur policies are not removed. Remove host grants manually if needed."
