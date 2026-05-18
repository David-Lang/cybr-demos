# Secrets Provider Sidecar + CyberArk Conjur Cloud — Demo Setup

The CyberArk **Secrets Provider for Kubernetes** runs as a **sidecar** container beside your application. It authenticates with a pod JWT, fetches Conjur variables, and writes a native Kubernetes Secret — no External Secrets Operator required.

## Main Entry Points

```bash
bash demos/secrets_manager/k8s/sidecar/setup.sh
bash demos/secrets_manager/k8s/sidecar/demo.sh
```

The interactive `demo.sh` script follows the same ENTER-to-advance style as `eso/demo.sh`. Expect roughly 10 minutes end to end.

## Deployment Context

This demo runs on any Kubernetes cluster with outbound HTTPS to CyberArk Cloud. It reuses the same Privilege Cloud safe (`k8s-eso`) and JWT authenticator (`authn-jwt/zg-eso`) as the ESO sub-demos.

The demo relies on `CYBR_DEMOS_PATH`, `demos/tenant_vars.sh`, and `demos/setup_env.sh`.

## Required Environment

| Requirement | Detail |
|---|---|
| `CYBR_DEMOS_PATH` | Repo root path |
| `demos/tenant_vars.sh` | `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET` |
| CyberArk tenant | Privilege Cloud, Conjur Cloud, ISPSS |
| Conjur JWT authenticator | `authn-jwt/zg-eso` with K8s OIDC as token source |
| Privilege Cloud safe | `k8s-eso` with Conjur Sync as a member |
| Kubernetes cluster | `kubectl` context set; cluster can pull `cyberark/secrets-provider-for-k8s` |

Optional: `SM_AUTHN_ID` (defaults to `zg-eso` in `setup.sh`).

## Relationship to the ESO Demos

| | `eso/` | `sidecar/` |
|---|---|---|
| Integration | External Secrets Operator | Secrets Provider for K8s |
| Where it runs | Cluster-wide controller | Sidecar in the app pod |
| Declarative API | SecretStore + ExternalSecret | `conjur-map` on a K8s Secret + pod annotations |
| Namespace | `external-secrets` | `sp-sidecar` |
| Safe | `k8s-eso` | `k8s-eso` (shared) |
| Refresh | `refreshInterval: 15s` | `conjur.org/secrets-refresh-interval: 15s` |

If you already ran the ESO demo, the safe, account, and Conjur Sync replication are in place.

## Setup Flow

### 1. Privilege Cloud safe

Reuse the `k8s-eso` safe from `eso/demo_setup.md` if it does not exist yet.

### 2. Run setup.sh

`setup.sh`:

1. Creates namespace `sp-sidecar`, service account, and RBAC for secret updates.
2. Builds `conjur-connect` ConfigMap (Conjur URLs + TLS cert fetched from `TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud`).
3. Applies the `db-credentials` secret mapping (`conjur-map`).
4. Applies three Conjur policies when tenant credentials are available.
5. Deploys `sidecar-demo-app` and waits for the sidecar to populate secret keys.

### 3. Manual policy application (if needed)

```bash
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")

apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(cat demos/secrets_manager/k8s/sidecar/conjur-policy/1-workload.yaml)"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(cat demos/secrets_manager/k8s/sidecar/conjur-policy/2-grant-safe-access.yaml)"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-jwt" \
  "$(cat demos/secrets_manager/k8s/sidecar/conjur-policy/3-grant-authenticator-access.yaml)"
```

## What Gets Deployed

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `sp-sidecar-sa` | ServiceAccount | `sp-sidecar` | JWT workload identity |
| `conjur-connect` | ConfigMap | `sp-sidecar` | Conjur URL + authn-jwt settings |
| `db-credentials` | Secret | `sp-sidecar` | `conjur-map` + populated username/password keys |
| `sidecar-demo-app` | Deployment | `sp-sidecar` | App + `cyberark-secrets-provider-for-k8s` sidecar |

## Cleanup

```bash
bash demos/secrets_manager/k8s/sidecar/remove.sh
```

## Troubleshooting Setup

| Symptom | Check |
|---|---|
| Secret has only `conjur-map`, no `username`/`password` | Sidecar logs: `kubectl logs -n sp-sidecar deploy/sidecar-demo-app -c cyberark-secrets-provider-for-k8s` |
| 401 / auth failure | Host in `authn-jwt/zg-eso/apps` and `k8s-eso/delegation/consumers` |
| `policy_invalid` — group not found | Conjur Sync on the `k8s-eso` safe in Privilege Cloud |
| `CONJUR_SSL_CERTIFICATE` missing | Re-run `setup.sh` — cert is fetched via openssl from your Conjur Cloud FQDN |
| ConfigMap URLs wrong | `TENANT_SUBDOMAIN` when running `setup.sh`; re-run after fixing |
| Image pull errors | Cluster egress to Docker Hub for `cyberark/secrets-provider-for-k8s` |
