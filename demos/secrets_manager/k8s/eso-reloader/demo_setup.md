# Auto-Rotate Kubernetes Secrets — Demo Setup

ESO polls CyberArk Conjur Cloud on a 15-second refresh interval and updates a native K8s Secret whenever the upstream password changes in Privilege Cloud. A sample application consumes the secret via volume mount and environment variables. Stakater Reloader triggers automatic pod restarts so environment variables always reflect the current credentials.

## Main Entry Point

```bash
bash demos/secrets_manager/k8s/eso-reloader/setup.sh
```

Then run the interactive demo:

```bash
bash demos/secrets_manager/k8s/eso-reloader/demo.sh
```

## Deployment Context

This demo runs on any Kubernetes cluster with outbound HTTPS to CyberArk Cloud. It reuses the same `authn-jwt/zg-eso` authenticator as the existing ESO demo but creates its own namespace, service account, safe, and host identity.

ESO must be installed cluster-wide (the setup script handles this if missing). The lab uses a single-node k3s cluster registered to Rancher.

The demo relies on shared tenant configuration from `demos/tenant_vars.sh` and helper functions from `demos/setup_env.sh`. `CYBR_DEMOS_PATH` must be set.

## Required Environment

| Requirement | Detail |
|---|---|
| `CYBR_DEMOS_PATH` | Repo root path |
| `demos/tenant_vars.sh` | `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET` |
| CyberArk tenant | Privilege Cloud, Conjur Cloud, ISPSS |
| Conjur JWT authenticator | `authn-jwt/zg-eso` configured with K8s OIDC as token source |
| Privilege Cloud safe | `k8s-eso` (shared with the existing ESO demo) with Conjur Sync as a member |
| Kubernetes cluster | kubectl context set, Helm available |
| k9s (optional) | For visual dashboard exploration |

## Relationship to the Existing ESO Demo

This demo shares the `authn-jwt/zg-eso` JWT authenticator with the existing `eso/` demo, and both use **the same** `refreshInterval: 15s` on the ExternalSecret. The differences:

| | `eso/` | `eso-reloader/` |
|---|---|---|
| Namespace | `external-secrets` | `eso-reloader` |
| Safe | `k8s-eso` | `k8s-eso` (shared) |
| Sample app | None | `rotation-demo-app` with volume + env consumption |
| Reloader | Not used | Auto pod restart on secret change |
| Focus | General ESO + Conjur walkthrough | Auto-rotation + env var refresh story |

## Setup Flow

### 1. Privilege Cloud Safe

This demo reuses the `k8s-eso` safe from the existing ESO demo. If you already ran the `eso/` demo, the safe, account, and Conjur Sync replication are already in place.

If not, create the safe following the steps in `eso/demo_setup.md`.

### 2. Run setup.sh

`setup.sh` performs the following:

1. Verifies ESO is installed cluster-wide (installs via Helm if missing).
2. Creates the `eso-reloader` namespace.
3. Creates the `eso-reloader-sa` service account.
4. Applies three Conjur policies (workload host, safe access, authenticator grant).
5. Applies the SecretStore (Conjur JWT auth) and ExternalSecret (15s refresh).
6. Deploys `rotation-demo-app` (consumes secrets via volume mount + env vars).
7. Installs Stakater Reloader if not present (auto pod restart on secret change).

### 3. Manual Policy Application (if needed)

If tenant credentials are not set in the environment, apply policies manually:

```bash
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")

apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(cat demos/secrets_manager/k8s/eso-reloader/conjur-policy/1-workload.yaml)"

apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" \
  "$(cat demos/secrets_manager/k8s/eso-reloader/conjur-policy/2-grant-safe-access.yaml)"

apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-jwt" \
  "$(cat demos/secrets_manager/k8s/eso-reloader/conjur-policy/3-grant-authenticator-access.yaml)"
```

## What Gets Deployed

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `eso-reloader` | Namespace | — | Isolated demo namespace |
| `eso-reloader-sa` | ServiceAccount | `eso-reloader` | JWT identity for Conjur auth |
| `conjur` | SecretStore | `eso-reloader` | Conjur Cloud connection + JWT auth config |
| `db-credentials` | ExternalSecret | `eso-reloader` | Declares Conjur variables + 15s refresh |
| `db-credentials` | Secret | `eso-reloader` | K8s Secret created and maintained by ESO |
| `rotation-demo-app` | Deployment | `eso-reloader` | Sample app with volume mount + env vars |
| `reloader` | Deployment | `reloader` | Watches secrets, triggers pod rolling restarts |

## Cleanup

```bash
bash demos/secrets_manager/k8s/eso-reloader/remove.sh
```

This removes all demo-specific K8s resources. ESO and Reloader are left installed as shared infrastructure. Conjur policies are not removed automatically.

## Troubleshooting Setup

| Symptom | Check |
|---|---|
| `no matches for kind "SecretStore"` | ESO CRDs not installed — `setup.sh` should handle this |
| Webhook connection refused | ESO pods not ready — `kubectl rollout status` the ESO deployments |
| `policy_invalid` — group not found | Conjur Sync not added to the Privilege Cloud safe |
| Identity token `access_denied` | Verify `CLIENT_ID` suffix matches tenant |
| 401 on ExternalSecret sync | Check the host is in `authn-jwt/zg-eso/apps` and `identity-path` matches |
| Deployment timeout | Check ESO logs: `kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50` |
