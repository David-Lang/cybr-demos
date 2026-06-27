# swa_k8s Demo — Implementation Status

## Latest Update (Current Session)

**Simplified AWS SPIFFE Integration** - Replaced complex Summon + PAM safe credential flow with simple `.env` files:

- ✅ Created pre-filled credential templates: `aws_credentials.env`, `azure_credentials.env`, `gcp_credentials.env`
- ✅ All credential files are gitignored
- ✅ Removed Summon dependency and authn-iam requirement
- ✅ Updated `setup.sh` to source credentials directly from `.env` files
- ✅ Created comprehensive documentation:
  - `QUICKSTART_AWS.md` - 5-minute quick start guide
  - `setup/cloud/README.md` - Cloud setup details
  - Updated `AWS_TESTING.md`, `LAB_CHECKLIST.md`, `IMPLEMENTATION_SUMMARY.md`

**User workflow now:** Fill in two `.env` files → Run `bash setup.sh --aws` → Test

**Status:** Ready for lab testing!

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

## Multi-Cloud SPIFFE Extension (In Progress)

This session added a multi-cloud JWT-SVID federation demo: `giftapp-swa` uses its SPIFFE JWT-SVID to authenticate directly to AWS S3, Azure Blob Storage, and GCP Cloud Storage — no cloud SDKs, pure stdlib HTTP.

### What Was Done This Session

**demo.sh rework**
- Renamed "Defended app" → "Secured app" throughout
- Restructured into 4 parts / 18 steps with volume architecture comparison as the focal point
- Step 7: side-by-side YAML showing hardcoded secret (6 keys incl. DB_PASS, GIFTAPP_API_KEY) vs. SWA secret (4 non-sensitive keys only)
- Step 15: changed from `kubectl rollout restart` to `/refresh` endpoint call

**GiftApp code changes**
- `main.go`: Added `/refresh` POST endpoint — forces fresh SWA auth without pod restart
- `cmd/giftapp/csp.go`: New file — complete `/csp-test?cloud=<aws|azure|gcp>` implementation:
  - `fetchSVID(ctx, socket, audience)` — fetches JWT-SVID for specified audience
  - `awsS3Test`: STS AssumeRoleWithWebIdentity → manual SigV4 S3 GET
  - `azureBlobTest`: client_credentials + JWT assertion → Bearer blob GET
  - `gcpStorageTest`: STS token exchange → generateAccessToken SA impersonation → Bearer GCS GET
  - Manual AWS SigV4 implementation (no SDK)
  - Returns `cspTestResult{Cloud, SpiffeID, Audience, Source, Content, Error}` as JSON

**compute_init/ubuntu**
- `install_azurecli.sh`: New — installs Azure CLI via Microsoft apt repo
- `install_gcpcli.sh`: New — installs Google Cloud CLI via Google apt repo
- `setup.sh`: Added `install_azurecli.sh` and `install_gcpcli.sh` to scripts array
- `setup_rancher.sh`: Added `install_docker.sh`, `install_terraform.sh`, `install_azurecli.sh`, `install_gcpcli.sh` to root_scripts

**Cloud setup scripts** (`setup/cloud/`)
- `vars.env`: New — cloud provider inputs + Conjur/Summon auth config
- `aws/setup.sh`: New — idempotent AWS bootstrap (OIDC provider, IAM role, S3 bucket, test file upload). Writes `aws_registered.env`.
- `aws/secrets.tmpl.yml`: New — Summon template for AWS credentials from CyberArk safe
- `azure/setup.sh`: New — idempotent Azure bootstrap (resource group, managed identity, federated credential, storage account, container, RBAC, test blob). Writes `azure_registered.env`.
- `azure/secrets.tmpl.yml`: New — Summon template for Azure SP credentials
- `gcp/setup.sh`: New — idempotent GCP bootstrap (workload identity pool, OIDC provider, SA, IAM binding, GCS bucket, test file). Writes `gcp_registered.env`.
- `gcp/secrets.tmpl.yml`: New — Summon template for GCP SA JSON key (`!var:file`)

**setup.sh (top-level)**
- Added `--aws`, `--azure`, `--gcp` flags
- Exports `SETUP_AWS`, `SETUP_AZURE`, `SETUP_GCP` (survives docker-group re-exec)
- Cloud section: loads `cloud/vars.env` and `cloud/*_credentials.env`, calls per-cloud setup scripts
- Simplified: no Summon, no PAM safe, direct credential loading from .env files

### Completed Tasks for AWS Testing

1. **✅ Registered `/csp-test` in main.go**
   - Added endpoint handler to mux registration block

2. **✅ Updated `giftapp-swa` deployment.yaml**
   - Added optional ConfigMap ref to `envFrom` in `setup/k8s/charts/giftapp-swa/templates/deployment.yaml`

3. **✅ Updated AWS setup script to write K8s ConfigMap**
   - `setup/cloud/aws/setup.sh` now creates/updates `giftapp-cloud-spiffe` ConfigMap
   - Automatically restarts `giftapp-swa` deployment after ConfigMap update

### Ready for Testing

The AWS integration is now ready to test. Spin up a fresh lab and:

1. Fill in `setup/cloud/vars.env` with AWS account ID and region
2. Fill in `setup/cloud/aws_credentials.env` with AWS access key and secret
3. Run `bash setup.sh --aws`
4. Test the endpoint: `kubectl exec -n <namespace> <giftapp-swa-pod> -- curl -sk "https://localhost:8443/csp-test?cloud=aws"`

**Quick Start:** See [`QUICKSTART_AWS.md`](QUICKSTART_AWS.md) for a 5-minute setup guide.

### Pending GCP Tasks (deferred)

- Azure and GCP implementations exist in `csp.go`
- Azure setup now patches `giftapp-cloud-spiffe` with `AZURE_SPIFFE_*` runtime config and restarts `giftapp-swa`
- GCP still needs the same non-clobbering ConfigMap update as AWS/Azure
- Azure and GCP still need fresh-lab validation

### CSP Bootstrap Credential Flow (Simplified)

```
User fills *_credentials.env → setup.sh sources credentials → cloud setup script creates resources
```

**Credential Files** (all gitignored, pre-created templates):
- `aws_credentials.env`: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
- `azure_credentials.env`: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET
- `gcp_credentials.env`: GOOGLE_APPLICATION_CREDENTIALS_JSON

**Note:** For production, use IAM roles, managed identities, or secrets managers instead of static credentials.

### CSP Authentication Flow (giftapp-swa runtime)

```
giftapp-swa → SWA socket → JWT-SVID → cloud STS/OIDC exchange → cloud access token → storage read
```

- AWS: audience `sts.amazonaws.com`, env vars `AWS_SPIFFE_ROLE_ARN`, `AWS_SPIFFE_BUCKET`, `AWS_SPIFFE_REGION`
- Azure: audience `api://AzureADTokenExchange`, env vars `AZURE_SPIFFE_CLIENT_ID`, `AZURE_SPIFFE_TENANT_ID`, `AZURE_SPIFFE_STORAGE_ACCOUNT`, `AZURE_SPIFFE_CONTAINER`
- GCP: audience = pool audience string, env vars `GCP_SPIFFE_POOL_AUDIENCE`, `GCP_SPIFFE_SA_EMAIL`, `GCP_SPIFFE_BUCKET`, `GCP_SPIFFE_PROJECT_ID`

Env vars come from `giftapp-cloud-spiffe` ConfigMap (optional, sourced from `*_registered.env` files written by cloud setup scripts).

## Next Steps (Original)

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
