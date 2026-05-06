# SWA K8s — Demo Setup

## Overview

`setup.sh` orchestrates the deployment end to end:

```
init_k8s.sh
  → vault/setup.sh
  → swa/setup.sh
  → sm/setup_swa_auth.sh
  → build_giftapp_images.sh   (only when GIFTAPP_REGISTRY is unset)
  → k8s/setup.sh

discover K8s OIDC
  → create PAM safe + synced secrets
  → register SWA control plane + install SWA Server/Agent
  → configure Conjur JWT auth for SWA-issued JWT-SVIDs
  → build/import local GiftApp images
  → deploy both app variants
```

## Before you start

### 1 — Tenant credentials

Edit `demos/tenant_vars.sh`:

```bash
LAB_ID="lab01"
TENANT_ID="aabbcc"
TENANT_SUBDOMAIN="mycompany"
CLIENT_ID="your-service-account@cyberark.cloud.XXXXX"
CLIENT_SECRET="your-client-secret"
```

### 2 — Demo variables

Review `setup/vars.env`. Most values default from `LAB_ID` and can be left unchanged for the standard single-node RKE2 lab:

| Variable | Description |
|----------|-------------|
| `GIFTAPP_REGISTRY` | Optional registry/repo prefix for `giftapp-hardcoded` and `giftapp-swa`; when unset, images are built locally and imported into RKE2 |
| `GIFTAPP_IMAGE_TAG` | GiftApp image tag; defaults to `latest` |
| `SWA_CONTAINER_IMAGES_S3` | S3 prefix for SWA image tarballs |
| `SWA_TF_PROVIDER_S3` | S3 prefix for the SWA Terraform provider |
| `SWA_TRUST_DOMAIN_NAME` | SWA trust domain name; defaults from `$LAB_ID` |
| `SWA_NODE_GROUP_NAME` | SWA unix node group name; defaults from `$LAB_ID` |
| `SWA_SOCKET_PATH` | SWA Agent socket path; defaults to `/tmp/swa-agent/public/api.sock` |

### 3 — GiftApp container images

The default lab path builds the GiftApp images from the source committed in this demo:

```bash
bash setup/k8s/build_giftapp_images.sh
```

That script builds:

- `localhost/giftapp-hardcoded:latest`
- `localhost/giftapp-swa:latest`

Then it imports both images into RKE2/containerd using:

```bash
sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock -n k8s.io images import <image-tar>
```

If `GIFTAPP_REGISTRY` is unset, the top-level `setup.sh` runs this build/import step automatically and writes `setup/k8s/giftapp_images.env`.

External registries are still supported. To use one, publish `giftapp-hardcoded` and `giftapp-swa`, then export `GIFTAPP_REGISTRY` and `GIFTAPP_IMAGE_TAG` before running setup.

### 4 — Confirm host prerequisites

The demo VM needs:

- AWS CLI access to `s3://mis-cybr-demos/pm/swa-container-images/`
- AWS CLI access to `s3://mis-cybr-demos/pm/terraform-provider/`
- `kubectl`
- `helm`
- Terraform
- Docker, unless you are using a pre-published external GiftApp registry
- RKE2 containerd tooling at `/var/lib/rancher/rke2/bin/ctr`

---

## Running setup

```bash
export CYBR_DEMOS_PATH=/path/to/cybr-demos
cd demos/secrets_manager/swa_k8s
bash setup.sh
```

For a full unattended setup and validation run with captured logs:

```bash
bash test_runner.sh
```

For post-deploy validation only:

```bash
bash validate.sh
```

### Step 1 — K8s OIDC discovery (`setup/k8s/init_k8s.sh`)

Extracts the Kubernetes cluster's OIDC public keys and writes them into `setup/vars.env` as `K8S_PUBLIC_KEYS`. These keys are used to configure the Conjur JWT authenticator that validates the SWA Server's projected service account token.

### Step 2 — PAM safe and secrets (`setup/vault/setup.sh`)

- Creates a Privilege Cloud safe named `$LAB_ID-swa-k8s`
- Adds the Conjur Sync member so secrets are published to Conjur
- Creates two accounts:
  - `giftapp-api-key` — the API key for the gift-card app (syncs to `data/vault/$SAFE_NAME/giftapp-api-key/password`)
  - `giftapp-db-pass` — the database password (syncs to `data/vault/$SAFE_NAME/giftapp-db-pass/password`)

### Step 3 — SWA Server and Agent (`setup/swa/setup.sh`)

1. Installs the SWA Terraform provider
2. Downloads/imports SWA container image tarballs from S3
3. Uses Terraform to create the trust domain, k8s_psat server group, SWA server, and unix workload node group
4. Installs SWA Server and SWA Agent with the vendored release Helm charts

Important lab-specific behavior:

- SWA image tarballs import into RKE2/containerd through `/run/k3s/containerd/containerd.sock`.
- SWA Agent Helm install sets `nodeAttestor.k8s_psat.audience=spire-server`; the default `swa-server` audience fails TokenReview in this lab.
- SWA Agent runs as root/privileged in this single-node lab so the unix workload attestor can inspect workload processes through host PID.
- The workload node group uses `unix.uid` and issues `spiffe://<trust-domain>/<node-group>/workload/1000` to `giftapp-swa`.
- `swa_registered.env` records the tenant SWA issuer URL: `https://<tenant>.secretsmgr.cyberark.cloud/api/swa/trust-domains/<trust-domain>`.

### Step 4 — Conjur JWT authenticator for giftapp-swa (`setup/sm/setup_swa_auth.sh`)

Configures `authn-jwt/$SM_SERVICE_NAME-swa` so `giftapp-swa` can authenticate to Conjur using SWA-issued JWT-SVIDs.

### Step 5 — Build local GiftApp images (`setup/k8s/build_giftapp_images.sh`)

When `GIFTAPP_REGISTRY` is unset, builds the local demo app images and imports them into RKE2/containerd. This step is skipped when an external registry is supplied.

### Step 6 — Deploy applications (`setup/k8s/setup.sh`)

Deploys both giftapp variants using Helm:

- `giftapp-hardcoded` + `mysql-hardcoded` into `$NAMESPACE_HARDCODED`
- `giftapp-swa` + `mysql-swa` into `$NAMESPACE_SWA`

---

## Directory structure

```
swa_k8s/
├── setup.sh                    # Orchestrator
├── demo.sh                     # Demo launcher
├── validate.sh                 # Non-interactive post-deploy validation
├── test_runner.sh              # Full setup + validation with artifacts
├── demo_setup.md               # This file
├── demo_validation.md          # Post-setup validation walkthrough
└── setup/
    ├── vars.env                # All configuration variables
    ├── vault/setup.sh          # PAM safe + account creation
    ├── sm/
    │   ├── setup_swa_auth.sh   # Conjur JWT authenticator for giftapp-swa
    │   ├── swa-workloads.yaml  # Base workload policy branch
    │   ├── authn-jwt-swa-svid.tmpl.yaml
    │   ├── workload-swa-svid.tmpl.yaml
    │   ├── add-to-authn.tmpl.yaml
    │   └── add-to-safe.tmpl.yaml
    ├── swa/
    │   ├── setup.sh            # Terraform registration + Helm installs
    │   ├── remove.sh           # Helm uninstall + Terraform destroy
    │   └── terraform/          # SWA control-plane Terraform config
    └── k8s/
        ├── init_k8s.sh         # Discover K8s OIDC public keys
        ├── build_giftapp_images.sh
        ├── giftapp/            # Local GiftApp source + Dockerfiles
        ├── setup.sh            # Helm deploy both apps
        ├── remove.sh           # Helm uninstall both apps
        └── charts/
            ├── giftapp-hardcoded/
            ├── mysql-hardcoded/
            ├── giftapp-swa/
            └── mysql-swa/
```
