# ESO + CyberArk Conjur Cloud — Demo Setup

External Secrets Operator (ESO) pulls credentials from CyberArk Conjur Cloud into native Kubernetes secrets using JWT authentication. Secrets originate in Privilege Cloud and sync to Conjur Cloud automatically. ESO handles retrieval and rotation — zero application code changes.

## Main Entry Point

```bash
bash demos/secrets_manager/k8s/eso/demo.sh
```

The interactive script walks through each layer of the integration with talk-track narration and live `kubectl` validation. Expect roughly 10 minutes end to end.

## Deployment Context

This demo runs on any Kubernetes cluster (Rancher, EKS, k3s, etc.) with outbound HTTPS to CyberArk Cloud. The lab deployment uses a single-node k3s cluster registered to Rancher.

The demo relies on shared tenant configuration from `demos/tenant_vars.sh` and helper functions from `demos/setup_env.sh`.

## Required Environment

| Requirement | Detail |
|---|---|
| `CYBR_DEMOS_PATH` | Repo root path |
| `demos/tenant_vars.sh` | `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET` |
| CyberArk tenant | Privilege Cloud, Conjur Cloud, ISPSS |
| Conjur JWT authenticator | `authn-jwt/zg-eso` configured with K8s OIDC as token source |
| Privilege Cloud safe | `k8s-eso` with Conjur Sync as a member |
| Kubernetes cluster | kubectl context set, Helm available |
| k9s (optional) | For visual dashboard exploration |

## Setup Flow

### 1. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true
```

Wait for all pods to be ready:

```bash
kubectl rollout status deployment -n external-secrets external-secrets
kubectl rollout status deployment -n external-secrets external-secrets-webhook
kubectl rollout status deployment -n external-secrets external-secrets-cert-controller
```

### 2. Create the ESO service account

```bash
kubectl create sa zg-eso-service-account -n external-secrets
```

### 3. Configure CyberArk — Privilege Cloud

1. Create a safe named `k8s-eso` in Privilege Cloud.
2. Add **Conjur Sync** (DAPService) as a safe member with read access.
3. Add the Conjur installer service account (`conjurinstaller@zach-lab`) with full admin access.
4. Create an account `account-ssh-user-1` in the `k8s-eso` safe (Platform: Unix SSH).
5. Wait for the Conjur Synchronizer to replicate the safe and account.

### 4. Configure CyberArk — Conjur Cloud Policies

Source the shared environment and obtain tokens:

```bash
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
set +e; set +u
identity_token=$(bash -c 'source "$CYBR_DEMOS_PATH/demos/setup_env.sh" && get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET"')
conjur_token=$(bash -c "source \"\$CYBR_DEMOS_PATH/demos/setup_env.sh\" && get_conjur_token \"\$TENANT_SUBDOMAIN\" \"$identity_token\"")
```

Apply the three policies in order:

```bash
# 1. Create host identity (policy branch: data)
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "append" "data" \
  demos/secrets_manager/k8s/eso/conjur-policy/1-workload.yaml

# 2. Grant safe access (policy branch: data)
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "append" "data" \
  demos/secrets_manager/k8s/eso/conjur-policy/2-grant-safe-access.yaml

# 3. Grant authenticator access (policy branch: conjur/authn-jwt)
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "append" "conjur/authn-jwt" \
  demos/secrets_manager/k8s/eso/conjur-policy/3-grant-authenticator-access.yaml
```

### 5. Set authenticator identity-path

If the JWT authenticator's `identity-path` does not match the host's policy branch:

```bash
apply_conjur_secret "$TENANT_SUBDOMAIN" "$conjur_token" \
  "conjur/authn-jwt/zg-eso/identity-path" "data/poc-workloads"
```

### 6. Apply K8s resources

Set `TENANT_SUBDOMAIN` and optional `SM_AUTHN_ID` (defaults to `zg-eso`), then render and apply:

```bash
export TENANT_SUBDOMAIN=your-subdomain
export SM_AUTHN_ID=zg-eso
envsubst < demos/secrets_manager/k8s/eso/secretstore.tmpl.yaml | kubectl apply -f -
kubectl apply -f demos/secrets_manager/k8s/eso/externalsecret.yaml
```

`secretstore.yaml` in the repo may contain a lab example URL; prefer `secretstore.tmpl.yaml` for new clusters.

## What Gets Deployed

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `external-secrets` | Deployment (3 pods) | `external-secrets` | ESO controller, webhook, cert-controller |
| `zg-eso-service-account` | ServiceAccount | `external-secrets` | JWT identity for Conjur auth |
| `conjur` | SecretStore | `external-secrets` | Conjur Cloud connection + JWT auth config |
| `conjur` | ExternalSecret | `external-secrets` | Declares which Conjur variables to fetch |
| `conjur-secrets` | Secret | `external-secrets` | Native K8s secret created by ESO |

## Troubleshooting Setup

| Symptom | Check |
|---|---|
| `no matches for kind "SecretStore"` | ESO CRDs not installed — reinstall with `--set installCRDs=true` |
| Webhook connection refused | ESO pods not ready — `kubectl rollout status` all three deployments |
| `policy_invalid` — group not found | Conjur Sync not added to the Privilege Cloud safe |
| Identity token `access_denied` | Verify `CLIENT_ID` suffix matches tenant (`zach-lab` not `zachlab`) |
| 401 on ExternalSecret sync | Check `identity-path` matches the host's policy branch |
