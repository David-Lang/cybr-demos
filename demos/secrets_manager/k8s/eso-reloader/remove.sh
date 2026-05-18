#!/bin/bash
# Cleanup: Auto-Rotate K8s Secrets — ESO + CyberArk Conjur Cloud
set -euo pipefail

NAMESPACE="eso-reloader"

echo "[INFO] Removing ESO Auto-Rotation Demo"

echo "[INFO] Deleting ExternalSecret"
kubectl delete externalsecret -n "$NAMESPACE" db-credentials --ignore-not-found

echo "[INFO] Deleting SecretStore"
kubectl delete secretstore -n "$NAMESPACE" conjur --ignore-not-found

echo "[INFO] Deleting deployment"
kubectl delete deployment -n "$NAMESPACE" rotation-demo-app --ignore-not-found

echo "[INFO] Deleting service account"
kubectl delete sa -n "$NAMESPACE" eso-reloader-sa --ignore-not-found

echo "[INFO] Deleting namespace"
kubectl delete ns "$NAMESPACE" --ignore-not-found

echo "[INFO] Cleanup complete"
echo "[NOTE] ESO and Reloader are left installed (shared infrastructure)."
echo "[NOTE] Conjur policies are not removed. Remove them manually if needed."
