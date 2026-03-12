# Kubernetes Demo Commands

This file is a post-install command reference for the Kubernetes Secrets Manager demo.

Start by loading the demo namespace:

```bash
cd demos/secrets_manager/k8s
source setup/vars.env
export DEMO_NAMESPACE="$SM_SERVICE_NAME"
echo "$DEMO_NAMESPACE"
```

## Core Checks

```bash
kubectl get all -n "$DEMO_NAMESPACE"
kubectl get secret -n "$DEMO_NAMESPACE"
kubectl get configmap -n "$DEMO_NAMESPACE"
kubectl get serviceaccount -n "$DEMO_NAMESPACE"
kubectl get role,rolebinding -n "$DEMO_NAMESPACE"
kubectl get secretstore,externalsecret -n "$DEMO_NAMESPACE"
kubectl get pods -n external-secrets
```

## Shared CyberArk Config

```bash
kubectl get configmap sm-configmap -n "$DEMO_NAMESPACE" -o yaml
kubectl describe configmap sm-configmap -n "$DEMO_NAMESPACE"
kubectl get serviceaccount poc-service-account -n "$DEMO_NAMESPACE" -o yaml
```

## K8s Secrets

Validate the native Kubernetes secret written by the provider init container:

```bash
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o yaml
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets
kubectl logs -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets -c cyberark-secrets-provider-for-k8s
```

Decode the values:

```bash
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o jsonpath='{.data.conjur-map}' | base64 -d; echo
```

## K8s Secrets FetchAll

Validate the fetch-all Kubernetes secret pattern:

```bash
kubectl get secret demo-k8-secret-fetch-all -n "$DEMO_NAMESPACE" -o yaml
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets-fetch-all
kubectl logs -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets-fetch-all -c cyberark-secrets-provider-for-k8s
```

List the secret keys that were populated:

```bash
kubectl get secret demo-k8-secret-fetch-all -n "$DEMO_NAMESPACE" -o json | jq -r '.data | keys[]'
```

## Push To File

Validate the sidecar-written file:

```bash
kubectl get pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file
kubectl exec -n "$DEMO_NAMESPACE" deploy/demo-push-to-file -c app-container -- \
  ls -l /opt/secrets/conjur
kubectl exec -n "$DEMO_NAMESPACE" deploy/demo-push-to-file -c app-container -- \
  cat /opt/secrets/conjur/credentials.yaml
kubectl logs -n "$DEMO_NAMESPACE" -l app=demo-push-to-file -c cyberark-secrets-provider-for-k8s
```

## Push To File FetchAll

Validate the fetch-all file pattern:

```bash
kubectl get pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file-fetch-all
kubectl exec -n "$DEMO_NAMESPACE" deploy/demo-push-to-file-fetch-all -c app-container -- \
  ls -l /opt/secrets/conjur
kubectl exec -n "$DEMO_NAMESPACE" deploy/demo-push-to-file-fetch-all -c app-container -- \
  cat /opt/secrets/conjur/credentials.yaml
kubectl logs -n "$DEMO_NAMESPACE" -l app=demo-push-to-file-fetch-all -c cyberark-secrets-provider-for-k8s
```

## External Secrets Operator

Validate ESO health and synced resources:

```bash
kubectl get secretstore,externalsecret -n "$DEMO_NAMESPACE"
kubectl describe secretstore conjur -n "$DEMO_NAMESPACE"
kubectl describe externalsecret conjur -n "$DEMO_NAMESPACE"
kubectl get secret conjur -n "$DEMO_NAMESPACE" -o yaml
kubectl get pods -n external-secrets
kubectl logs -n external-secrets deploy/external-secrets
```

Show the synced keys:

```bash
kubectl get secret conjur -n "$DEMO_NAMESPACE" -o json | jq -r '.data | keys[]'
```

## JWT Inspection

Read and decode the projected service account token:

```bash
kubectl exec -n "$DEMO_NAMESPACE" deploy/alpine-curl -- \
  cat /var/run/secrets/tokens/jwt > /tmp/k8s-demo.jwt
jq -R 'split(".") | {header: .[0] | @base64d | fromjson, payload: .[1] | @base64d | fromjson}' \
  /tmp/k8s-demo.jwt
```

## Curl Direct

Inspect the helper pod environment:

```bash
kubectl get pod -n "$DEMO_NAMESPACE" -l app=alpine-curl
kubectl exec -n "$DEMO_NAMESPACE" deploy/alpine-curl -- env | sort
kubectl get configmap demo-scripts -n "$DEMO_NAMESPACE" -o yaml
```

Test direct CyberArk authentication and retrieval:

```bash
kubectl exec -it -n "$DEMO_NAMESPACE" deploy/alpine-curl -- sh
JWT=$(cat /var/run/secrets/tokens/jwt)
AUTHN_URL="$CONJUR_AUTHN_URL/conjur/authenticate"
SESSION_TOKEN=$(curl -sk \
  -X POST "$AUTHN_URL" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept-Encoding: base64' \
  --data-urlencode "jwt=$JWT")
echo "$SESSION_TOKEN"

SECRET_URL="$CONJUR_APPLIANCE_URL/secrets/conjur/variable/$username"
curl -sk \
  --request GET \
  --url "$SECRET_URL" \
  --header "Authorization: Token token=\"$SESSION_TOKEN\""
exit
```

## Troubleshooting

```bash
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets-fetch-all
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file-fetch-all
kubectl describe secretstore conjur -n "$DEMO_NAMESPACE"
kubectl describe externalsecret conjur -n "$DEMO_NAMESPACE"
```
