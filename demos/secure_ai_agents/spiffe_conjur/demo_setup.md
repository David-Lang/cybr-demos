# Demo Setup

This demo stands up a local Kubernetes cluster (minikube) running SPIRE, wires
SPIRE's JWT-SVIDs into a CyberArk Conjur Cloud `authn-jwt` authenticator, and
deploys two AI agent pods so the audience can compare the BEFORE state
(hardcoded API key in env) with the AFTER state (vaulted secret retrieved with
a short-lived access token).

The CyberArk doc this implements:
[Authenticate AI agents with JWT SVIDs (SPIFFE)](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/operations/authn/authenticate-ai-spiffe.htm).

## Main Entry Point

From the demo root:

```bash
cd $CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur
./setup.sh
```

`setup.sh` calls four stage scripts in order. Each one is also runnable
individually for re-runs and troubleshooting:

| Stage | Script | What it does |
|---|---|---|
| 1 | `setup/spire/setup.sh` | minikube + helm install spire-crds + spire (OIDC enabled) + build spire-tools image into minikube + apply ClusterSPIFFEID |
| 2 | `setup/workloads/setup.sh` | apply BEFORE pod (`vulnerable-agent`) + render and apply AFTER pod (`attested-agent`) |
| 3 | `setup/oidc/setup.sh` | start cloudflared tunnel against the SPIRE OIDC service + helm-upgrade SPIRE Server jwtIssuer to the tunnel URL |
| 4 | `setup/conjur/setup.sh` | load four Conjur Cloud policies + set authn-jwt variables + enable authenticator + seed demo secret + patch in-cluster ConfigMap |

## Deployment Context

This demo runs on a **local laptop or any machine that can run Docker +
minikube**. Unlike most cybr-demos which target a remote Ubuntu lab VM, the
SPIRE control plane and the demo workloads are intentionally local so the
audience can `kubectl exec` interactively without VPN or jump host friction.

Conjur Cloud, by contrast, is your real CyberArk SaaS tenant
(`$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud`). The cloudflared tunnel in
stage 3 is what lets your local SPIRE OIDC discovery provider be reached by
Conjur Cloud's authn-jwt JWKS lookup.

## Required Environment

Standard cybr-demos environment must already be set:

- `CYBR_DEMOS_PATH` — path to this repo
- `LAB_ID` — set in `demos/tenant_vars.sh`
- `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET` — Conjur Cloud
  service user credentials, also in `demos/tenant_vars.sh`. The user must have
  the **Authn_Admins** (or **Conjur_Cloud_Admins**) group so policy loads
  succeed.

This demo's own configuration lives in **`setup/vars.env`** (gitignored).
A template lives at **`setup/vars.env.example`** (tracked); the top-level
`setup.sh` will auto-copy the template on first run if `vars.env` is missing.
You can also seed it manually:

```bash
cp setup/vars.env.example setup/vars.env
vi setup/vars.env
```

Notable values:

- `USECASE_ID` — derived from `$LAB_ID` (default: `<LAB_ID>-spiffe-conjur`)
- `MINIKUBE_PROFILE` — minikube profile name
- `TRUST_DOMAIN` — SPIRE trust domain (`<USECASE_ID>.local` by default)
- `SPIFFE_HOST_ID` — the SPIFFE ID minted for the attested workload; this
  string MUST match the host annotation in the Conjur policy
- `CONJUR_AUTHN_SERVICE_ID` — the authn-jwt service id (default: `spiffe-auth`)
- `CONJUR_SECRET_VARIABLE` — the demo secret's full Conjur path
- `DEMO_SECRET_VALUE` — the value seeded into Conjur Cloud
- `CLOUDFLARED_TUNNEL_NAME` — leave blank for ephemeral quick-tunnel URLs;
  set to a pre-created named tunnel for a stable URL across demo sessions

## Local Tool Prerequisites

The demo VM (or laptop) needs:

- `docker` (running)
- `minikube >= 1.34`
- `kubectl >= 1.30`
- `helm >= 3.14`
- `cloudflared` — `brew install cloudflared` (macOS) or
  `compute_init/ubuntu/install_spiffe_conjur_prereqs.sh` (Ubuntu)
- `envsubst` — usually part of the `gettext` package
- `jq`, `curl`, `openssl`

Approximately 6 GB free RAM and 20 GB disk are required for the minikube VM.

## Setup Flow

### Stage 1 — SPIRE on minikube

`setup/spire/setup.sh`:

1. Starts (or reuses) the `MINIKUBE_PROFILE` minikube cluster.
2. Adds the `spiffe/spire` Helm repo.
3. Installs `spire-crds` (chart 0.5.0) into namespace `spire-mgmt`.
4. Installs `spire` (chart 0.28.4) with `helm-values/spire-values.yaml` and
   `--set global.spire.trustDomain=$TRUST_DOMAIN`.
5. `eval $(minikube docker-env)` then `docker build` the `spire-tools` image
   directly into the minikube image store (no registry round-trip).
6. Applies the `workloads` namespace and the `workloads-default` ClusterSPIFFEID.

### Stage 2 — Workloads

`setup/workloads/setup.sh`:

1. Applies `manifests/00-vulnerable-agent.yaml` (the BEFORE pod with hardcoded
   `OPENAI_API_KEY` in env via a K8s Secret).
2. Renders `manifests/40-attested-agent.yaml.tpl` with `envsubst` (filling in
   the trust domain, Conjur tenant URL, SPIFFE ID, etc. from `vars.env`).
3. Applies the rendered manifest. The `attested-agent` pod has zero secret
   references; its only credential surface is a SPIFFE CSI volume.

### Stage 3 — Cloudflared OIDC tunnel

`setup/oidc/setup.sh`:

1. `kubectl port-forward` the in-cluster `spire-spiffe-oidc-discovery-provider`
   service to `localhost:$CLOUDFLARED_LOCAL_PORT`.
2. Starts `cloudflared` against that local port (quick tunnel by default,
   named tunnel if `CLOUDFLARED_TUNNEL_NAME` is set).
3. Captures the assigned `https://*.trycloudflare.com` URL.
4. Probes `<URL>/keys` to confirm Conjur Cloud will be able to fetch the JWKS.
5. Writes `OIDC_PUBLIC_URL=...` to `setup/.oidc.env` for stage 4.
6. `helm upgrade --reuse-values --set global.spire.jwtIssuer=$OIDC_PUBLIC_URL`
   so newly-issued JWT-SVIDs have an `iss` claim Conjur Cloud will accept.
7. `kubectl rollout restart` SPIRE Server so the new issuer takes effect.

### Stage 4 — Conjur Cloud authn-jwt + secret

`setup/conjur/setup.sh`:

1. `get_identity_token` (ISPSS) → `get_conjur_token` (Conjur Cloud session token).
2. Renders the four policy templates with `envsubst` (filling in
   `SPIFFE_HOST_ID`, `CONJUR_AUTHN_SERVICE_ID`, `CONJUR_HOSTS_BRANCH`).
3. Loads each policy at the correct branch via `apply_conjur_policy`:
   - `01-authn-jwt-spiffe.yaml` → `conjur/authn-jwt`
   - `02-spiffe-apps-hosts.yaml` → `data`
   - `03-authn-jwt-grant.yaml` → `conjur/authn-jwt/<service-id>`
   - `04-secret-access.yaml` → `data`
4. Sets the four authenticator variables (jwks-uri, issuer, token-app-property,
   identity-path) via `apply_conjur_secret`.
5. Enables the authenticator via `activate_conjur_service`.
6. Seeds `DEMO_SECRET_VALUE` into `data/spiffe-secrets/openai-api-key`.
7. Patches the in-cluster `conjur-config` ConfigMap so the attested-agent uses
   the right `CONJUR_URL`.

## What Gets Deployed

In your local minikube cluster:

| Namespace | Resource | Purpose |
|---|---|---|
| `spire-mgmt` | StatefulSet `spire-server` | SPIRE control plane root of trust |
| `spire-mgmt` | DaemonSet `spire-agent` | per-node attestation (`k8s_psat`) |
| `spire-mgmt` | DaemonSet `spire-spiffe-csi-driver` | mounts Workload API socket into pods |
| `spire-mgmt` | Deployment `spire-spiffe-oidc-discovery-provider` | serves `/keys` JWKS |
| `spire-mgmt` | Deployment `spire-controller-manager` | reconciles `ClusterSPIFFEID` CRs |
| (cluster) | `ClusterSPIFFEID workloads-default` | identity policy for demo workloads |
| `vulnerable-agents` | Pod `vulnerable-agent` + Secret `openai-credentials` | the BEFORE state |
| `workloads` | Pod `attested-agent` + ConfigMap `conjur-config` + ServiceAccount `agent` | the AFTER state |

In your CyberArk Conjur Cloud tenant:

| Branch | Object | Purpose |
|---|---|---|
| `conjur/authn-jwt/spiffe-auth` | webservice + 4 variables + apps/operators groups | the JWT authenticator |
| `data/spiffe-apps` | host id `spiffe://<trust-domain>/...` | the workload identity |
| `data/spiffe-secrets` | variable `openai-api-key` + consumers group | the vaulted secret |

## Troubleshooting Setup

### `helm install spire` times out

Check `kubectl -n spire-mgmt get pod`. If `spire-server-0` is `Pending`, the
PVC may have failed to bind — minikube's default storage class should handle
this. Try `minikube delete -p $MINIKUBE_PROFILE` and re-run stage 1.

### Stage 3: `cloudflared did not produce a public URL`

Check `setup/oidc/state/cloudflared.log`. Quick tunnels are occasionally
slow to assign a URL. Re-run `setup/oidc/setup.sh`. If it persists, install or
upgrade `cloudflared` (`brew upgrade cloudflared`).

### Stage 4: `failed to authenticate to Conjur` or HTTP 401

The service user in `tenant_vars.sh` must have `Authn_Admins` or
`Conjur_Cloud_Admins`. Verify with the Identity Admin UI or by trying the
`portfolio_workflow` setup which uses the same credentials.

### Stage 4 succeeds but the demo's step 5 returns HTTP 401

The JWT-SVID's `iss` claim doesn't match Conjur's `issuer` variable. This
happens after a `cloudflared` quick-tunnel restart. Recovery:

```bash
setup/oidc/setup.sh        # picks up a new tunnel URL
setup/conjur/setup.sh      # propagates the URL to Conjur + re-aligns SPIRE
```

The named-tunnel mode in `setup/vars.env` avoids this entirely if you'll be
demoing more than once.

### Workload pod stuck in `ContainerCreating` with CSI errors

Confirm the SPIFFE CSI Driver is healthy:

```bash
kubectl -n spire-mgmt get ds spire-spiffe-csi-driver
kubectl -n spire-mgmt logs -l app.kubernetes.io/name=spire-spiffe-csi-driver --tail=50
```
