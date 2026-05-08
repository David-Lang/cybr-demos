# swa_k8s Demo — Implementation Status

## Goal

Attack-vs-defend K8s demo showing CyberArk SWA Secure Workload Access:

- `giftapp-hardcoded`: K8s Secrets expose credentials at `/etc/secrets/` and through the K8s API.
- `giftapp-swa`: app fetches secrets at runtime using a SPIFFE JWT-SVID from the SWA Agent socket.

## Current Architecture

The demo follows the `swa-release-1-0-3` Kubernetes deployment model:

- SWA container image tarballs are downloaded from `s3://mis-cybr-demos/pm/swa-release-1-0-3/container-images/`.
- Images are imported into RKE2/containerd.
- The SWA Terraform provider registers the trust domain, server group, server, and unix workload node group.
- `swa-server` and `swa-agent` are installed with Helm chart archives from `s3://mis-cybr-demos/pm/swa-release-1-0-3/helm/`.
- `swa-agent` runs as a DaemonSet and exposes `/tmp/swa-agent/public/api.sock` through a hostPath.
- `giftapp-swa` mounts `/tmp/swa-agent` and uses `SPIFFE_ENDPOINT_SOCKET=unix:///tmp/swa-agent/public/api.sock`.

## Implemented

- Added SWA image import from `SWA_CONTAINER_IMAGES_S3`.
- Image import targets the RKE2 containerd socket at `/run/k3s/containerd/containerd.sock`.
- Added Terraform provider install from `SWA_TF_PROVIDER_S3`.
- Added Terraform config under `setup/swa/terraform`.
- Rewrote `setup/swa/setup.sh` to:
  1. install the Terraform provider,
  2. import SWA container images,
  3. register SWA resources with Terraform,
  4. write `swa_registered.env`,
  5. install `swa-server` and `swa-agent` with Helm.
- Helm install sets `nodeAttestor.k8s_psat.audience=spire-server`; without this, SWA Agent attestation fails with a TokenReview audience mismatch.
- SWA Agent runs as root/privileged in this single-node lab so the unix workload attestor can inspect workload processes through host PID.
- Workload node group uses Kubernetes namespace and service account attributes and mints `spiffe://<trust-domain>/<node-group>/workload/<namespace>/giftapp-swa-sa` for `giftapp-swa`.
- `swa_registered.env` uses the tenant SWA issuer URL, for example `https://<tenant>.secretsmgr.cyberark.cloud/api/swa/trust-domains/<trust-domain>`.
- Rewrote `setup/swa/remove.sh` to uninstall Helm releases and destroy Terraform resources.
- Updated `giftapp-swa` socket settings back to the release chart path.
- Kept the second Conjur JWT authenticator for `giftapp-swa` JWT-SVIDs.
- Added local GiftApp source under `setup/k8s/giftapp`.
- Added `setup/k8s/build_giftapp_images.sh` to build `giftapp-hardcoded` and `giftapp-swa`, save them as tarballs, import them into RKE2/containerd, and write `setup/k8s/giftapp_images.env`.
- Updated `setup/k8s/setup.sh` to source `giftapp_images.env` and install both GiftApp Helm charts with `image.pullPolicy=IfNotPresent`.
- Updated top-level `setup.sh` to build/import local GiftApp images when `GIFTAPP_REGISTRY` is not supplied.
- Added `validate.sh` for non-interactive post-deploy validation.
- Added `test_runner.sh` for full setup plus validation with captured artifacts.

## EC2 Test Status

Validated on a fresh Ubuntu EC2 lab host:

- Tenant variables are present in the `ubuntu` login shell.
- K8s OIDC discovery works.
- SWA Terraform provider downloads and installs from S3.
- SWA container images download from S3 and import into RKE2.
- Terraform `init`, `validate`, and `apply` work.
- `swa-server` and `swa-agent` install with Helm and are `Running`.
- SWA Agent starts its API socket at `/tmp/swa-agent/public/api.sock`.
- Local GiftApp images build and import into RKE2.
- `giftapp-hardcoded`, `mysql-hardcoded`, `giftapp-swa`, and `mysql-swa` are `Running`.
- `giftapp-swa` fetched both demo secrets through SWA JWT-SVID and Conjur.
- `validate.sh` passes end to end on the EC2 deployment.
- Verified defended health response:
  ```json
  {"mode":"swa","secrets":{"dbPassword":"present","giftappApiKey":"present"},"swaReady":true}
  ```

## GiftApp Images

`setup/k8s/setup.sh` needs two application images:

- `${GIFTAPP_REGISTRY}/giftapp-hardcoded:${GIFTAPP_IMAGE_TAG}`
- `${GIFTAPP_REGISTRY}/giftapp-swa:${GIFTAPP_IMAGE_TAG}`

Default path for this single-node RKE2 lab:

1. If `GIFTAPP_REGISTRY` is not exported, `setup.sh` runs `setup/k8s/build_giftapp_images.sh`.
2. The script builds:
   - `localhost/giftapp-hardcoded:latest`
   - `localhost/giftapp-swa:latest`
3. The script imports both images into RKE2/containerd with:
   ```bash
   sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock -n k8s.io images import <image-tar>
   ```
4. The script writes `setup/k8s/giftapp_images.env`.
5. `setup/k8s/setup.sh` sources `giftapp_images.env` before installing the GiftApp Helm charts.

External registry path:

1. Publish `giftapp-hardcoded` and `giftapp-swa` to a reachable registry.
2. Set `GIFTAPP_REGISTRY` and `GIFTAPP_IMAGE_TAG` to match that registry.
3. Run `bash setup.sh`.

## Next Steps

For a fresh run:

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
bash setup.sh
```

Validate:

```bash
bash validate.sh
```

For a full unattended setup and validation run with logs:

```bash
bash test_runner.sh
```

## Important Assumptions

- The SWA image tarball names are `swa-server-0.0.0-SNAPSHOT-<arch>.tar` and `swa-agent-0.0.0-SNAPSHOT-<arch>.tar`.
- `amd64` and `arm64v8` are the architecture suffixes used by the release image tarballs.
- `giftapp-swa` runs under the `giftapp-swa-sa` Kubernetes service account, matching `SWA_WORKLOAD_SPIFFE_ID`.
