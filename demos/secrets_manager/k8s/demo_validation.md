# Kubernetes Demo Walkthrough

This guide starts after `./setup.sh` has completed successfully and the Helm chart has already been deployed.

This repo deploys the demo through the Rancher-based lab setup.

The validation patterns in this walkthrough are standard Kubernetes patterns. They are intended to be conceptually valid on other conformant Kubernetes platforms, including OpenShift, as long as the cluster supports projected service account tokens, the required provider or operator components, and the CyberArk workload identity mapping.

The goal is to help a new user validate what Helm installed and understand how CyberArk Secrets Manager delivers secrets into workloads.

## Start Here

Deployment context:

- Repo automation and `setup.sh` assume the Rancher-based lab path.
- The workload validation steps below focus on standard Kubernetes resources and behavior.

Load the demo namespace:

```bash
cd demos/secrets_manager/k8s
source setup/vars.env
export DEMO_NAMESPACE="$SM_SERVICE_NAME"
echo "$DEMO_NAMESPACE"
kubectl get all -n "$DEMO_NAMESPACE"
```

You should see these main demo workloads:

- `demo-k8-secrets`
- `demo-k8-secrets-fetch-all`
- `demo-push-to-file`
- `demo-push-to-file-fetch-all`
- `alpine-curl`

You should also see these supporting resources:

- `sm-configmap`
- `poc-service-account`
- `SecretStore` and `ExternalSecret` objects

## What Helm Installed

The Helm chart for this demo renders resources from:

- `setup/k8s/charts/poc-sm/templates/demo-k8s-secrets.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-k8s-secrets-fetch-all.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-push-to-file.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-push-to-file-fetch-all.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-eso-sm.yaml`
- `setup/k8s/charts/poc-sm/templates/alpine-curl.yaml`
- `setup/k8s/charts/poc-sm/templates/namespace.yaml`

After Helm deploys the chart, the common building blocks in the namespace are:

- Namespace for the demo
- `sm-configmap` with CyberArk connection settings
- `poc-service-account`
- RBAC allowing the workload to read and update Kubernetes secrets

Validate them:

```bash
kubectl get configmap sm-configmap -n "$DEMO_NAMESPACE" -o yaml
kubectl get serviceaccount poc-service-account -n "$DEMO_NAMESPACE" -o yaml
kubectl get role,rolebinding -n "$DEMO_NAMESPACE"
```

The important CyberArk values are:

- `CONJUR_APPLIANCE_URL`
- `CONJUR_AUTHN_URL`
- `AUTHENTICATOR_ID`
- `CONJUR_SSL_CERTIFICATE`

These are the main values the integrations use to talk to CyberArk Secrets Manager.

## JWT Authentication Model

Every demo pattern in this namespace uses the Kubernetes service account token projected into the pod at:

```text
/var/run/secrets/tokens/jwt
```

CyberArk validates that JWT and maps its `sub` claim to the configured workload identity.

Inspect the token from the helper pod:

```bash
kubectl exec -n "$DEMO_NAMESPACE" deploy/alpine-curl -- \
  cat /var/run/secrets/tokens/jwt > /tmp/k8s-demo.jwt

jq -R 'split(".") | {header: .[0] | @base64d | fromjson, payload: .[1] | @base64d | fromjson}' \
  /tmp/k8s-demo.jwt
```

Focus on:

- `sub`
- `aud`
- namespace and service account details in the payload

## Pattern 1: K8s Secrets

What it does:

- Creates a native Kubernetes `Secret` named `db-credential`
- Adds a `conjur-map` that maps Kubernetes secret keys to CyberArk secret IDs
- Uses `cyberark-secrets-provider-for-k8s` as an init container
- Writes secret values into the Kubernetes secret before the app container starts
- Exposes those values to the app with `secretKeyRef`

Validate the result:

```bash
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o yaml
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets
```

Decode the secret values:

```bash
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get secret db-credential -n "$DEMO_NAMESPACE" -o jsonpath='{.data.conjur-map}' | base64 -d; echo
```

What to validate:

- The pod is running
- The `db-credential` secret exists
- The secret contains `username`, `password`, and `conjur-map`
- The application pod started after the provider init container completed

CyberArk behavior:

- Authenticate the pod with JWT
- Read the requested secret IDs from CyberArk
- Populate the Kubernetes secret
- Let the application consume a standard Kubernetes secret without talking to CyberArk directly

## Pattern 2: K8s Secrets FetchAll

What it changes:

- The seed secret contains `conjur-map: "*": "*"`
- The provider is instructed to fetch everything available to the workload
- The application imports all keys from that generated Kubernetes secret with `envFrom`

Validate the result:

```bash
kubectl get secret demo-k8-secret-fetch-all -n "$DEMO_NAMESPACE" -o yaml
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets-fetch-all
```

What to validate:

- The pod is running
- The secret exists and contains more than the seed `conjur-map`
- The workload was able to populate a Kubernetes secret from all authorized variables

CyberArk behavior:

- The workload authenticates once
- The provider fetches all authorized variables for that identity
- Matching values are written into the Kubernetes secret
- The app consumes the full set as environment variables

This pattern is useful when you want broad secret sync for a workload, but it also increases the blast radius if the workload is over-permissioned.

## Pattern 3: Push To File

What it does:

- Runs the provider as a sidecar
- Mounts a shared in-memory volume into both containers
- Writes secrets into `/opt/secrets/conjur/credentials.yaml`
- Refreshes the file on an interval

Validate the result:

```bash
kubectl get pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file
kubectl exec -n "$DEMO_NAMESPACE" deploy/demo-push-to-file -c app-container -- \
  cat /opt/secrets/conjur/credentials.yaml
```

What to validate:

- The pod is running
- The file exists in the shared volume
- The file contains the expected secret keys and values
- The app container can read the file written by the sidecar

CyberArk behavior:

- The sidecar authenticates with the pod JWT
- The sidecar retrieves the requested variables from CyberArk
- The sidecar renders a YAML file into the shared volume
- The app reads the file locally without embedding secrets into the pod spec

## Pattern 4: Push To File FetchAll

What it changes:

- Instead of listing individual variables, it asks for all secrets with:

```text
conjur.org/conjur-secrets.test-app: "*"
```

Validate the result:

```bash
kubectl get pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file-fetch-all
kubectl exec -n "$DEMO_NAMESPACE" deploy/demo-push-to-file-fetch-all -c app-container -- \
  cat /opt/secrets/conjur/credentials.yaml
```

CyberArk behavior:

- Same sidecar flow as Push To File
- Broader retrieval scope
- File is regenerated as the sidecar refreshes secrets

This is the file-based equivalent of FetchAll and should be treated with the same caution around workload permissions.

## Pattern 5: External Secrets Operator

What it does:

- Creates a `SecretStore` called `conjur`
- Configures ESO to authenticate to CyberArk with the pod service account JWT
- Creates an `ExternalSecret` that syncs remote CyberArk variables into a Kubernetes secret named `conjur`

Validate the result:

```bash
kubectl get secretstore,externalsecret -n "$DEMO_NAMESPACE"
kubectl get secretstore conjur -n "$DEMO_NAMESPACE" -o yaml
kubectl get externalsecret conjur -n "$DEMO_NAMESPACE" -o yaml
kubectl get secret conjur -n "$DEMO_NAMESPACE" -o yaml
kubectl get pods -n external-secrets
```

What to validate:

- The `SecretStore` is ready
- The `ExternalSecret` is synced
- The generated Kubernetes secret `conjur` exists
- The secret contains the expected keys from CyberArk
- The ESO controller is healthy

CyberArk behavior:

- ESO requests a service account token for the referenced service account
- ESO authenticates to CyberArk using the JWT authn service
- ESO reads the remote variables defined in `remoteRef.key`
- ESO creates and refreshes a standard Kubernetes secret

The difference from the provider-based patterns is that ESO is a controller-driven sync model, not an app-side init or sidecar model.

## Pattern 6: Curl Direct

The helper pod mounts:

- The projected JWT
- The CyberArk config from `sm-configmap`
- Environment variables containing the secret IDs

Inspect the helper pod:

```bash
kubectl get pod -n "$DEMO_NAMESPACE" -l app=alpine-curl
kubectl exec -n "$DEMO_NAMESPACE" deploy/alpine-curl -- env | sort
```

The `demo-scripts` ConfigMap includes a direct retrieval example. You can view it with:

```bash
kubectl get configmap demo-scripts -n "$DEMO_NAMESPACE" -o yaml
```

Direct retrieval flow:

1. Read the pod JWT from `/var/run/secrets/tokens/jwt`
2. POST it to the CyberArk JWT authenticator endpoint
3. Receive a session token
4. Use that session token to request a secret value directly from the CyberArk API

This pattern shows the raw API flow without ESO or the Secrets Provider abstractions.

Validate the API flow from inside the helper pod:

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

Validate it by confirming:

- The helper pod has the JWT token mounted
- The helper pod has `CONJUR_AUTHN_URL`
- The helper pod knows the secret IDs from environment variables
- A manual API call can authenticate and retrieve a secret

## Compare The Patterns

K8s Secrets:

- Best when the app already expects native Kubernetes secrets
- Uses init-container injection into a Kubernetes secret

Push To File:

- Best when the app wants a local file
- Uses a sidecar and shared volume

FetchAll:

- Best for broad retrieval demos or dynamic secret sets
- Higher permission sensitivity

ESO:

- Best when you want controller-managed sync into Kubernetes secrets
- Does not require app-side init or sidecar provider logic

Curl Direct:

- Best for learning and debugging the raw CyberArk JWT auth flow
- Closest to the underlying API behavior

## Troubleshooting

Provider logs:

```bash
kubectl logs -n "$DEMO_NAMESPACE" deploy/demo-k8-secrets -c cyberark-secrets-provider-for-k8s
kubectl logs -n "$DEMO_NAMESPACE" deploy/demo-push-to-file -c cyberark-secrets-provider-for-k8s
kubectl logs -n "$DEMO_NAMESPACE" deploy/demo-push-to-file-fetch-all -c cyberark-secrets-provider-for-k8s
```

ESO logs:

```bash
kubectl logs -n external-secrets deploy/external-secrets
```

Resource inspection:

```bash
kubectl describe secretstore conjur -n "$DEMO_NAMESPACE"
kubectl describe externalsecret conjur -n "$DEMO_NAMESPACE"
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file
```

If something fails, check these first:

- The pod is using `poc-service-account`
- The pod has `/var/run/secrets/tokens/jwt`
- `CONJUR_AUTHN_URL` points to the expected JWT authenticator
- The workload identity in CyberArk matches the service account subject
- The secret IDs from `setup/vars.env` exist and are authorized for the workload
