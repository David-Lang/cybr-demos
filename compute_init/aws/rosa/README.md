# ROSA Setup (from an existing AWS EC2)

Scripts to stand up (or connect to) a **Red Hat OpenShift Service on AWS (ROSA)**
cluster from an already-provisioned Ubuntu EC2 instance, and to write a working
kubeconfig for `kubectl` / `k9s`.

> There is no native CloudFormation resource for a ROSA cluster — ROSA is created
> through the `rosa` CLI against the Red Hat OpenShift Cluster Manager (OCM) API.
> These scripts run that flow from an EC2 admin host.

## Prerequisites

1. **Base tooling** — the host has already run
   `compute_init/ubuntu/setup.sh`, which installs `aws`, `jq`, `kubectl`,
   `helm`, and `k9s`. This script adds the ROSA-specific `oc` and `rosa` CLIs.
2. **AWS credentials** — available via the EC2 instance role or `aws configure`.
3. **Red Hat OCM offline token** — from
   <https://console.redhat.com/openshift/token/rosa>.
4. **ROSA enabled** in the AWS account (ELB service-linked role + service quotas).

## Files

- `install_oc.sh` — installs the OpenShift CLI (`oc`).
- `install_rosa.sh` — installs the ROSA CLI (`rosa`).
- `setup.sh` — main entry point: installs `oc`/`rosa`, provisions or connects to
  a ROSA cluster, backs up any existing kubeconfig, and writes the new one.

## Usage

Fill in the `CONFIG` block at the top of `setup.sh` (or pass values via
environment variables), then run it:

```bash
export ROSA_TOKEN="<red-hat-ocm-offline-token>"
export CLUSTER_NAME="rosa-demo"
export REGION="us-east-1"

./compute_init/aws/rosa/setup.sh
```

### Connect to an existing cluster instead of creating one

```bash
export ROSA_TOKEN="<token>"
export CLUSTER_NAME="rosa-demo"
export CREATE_CLUSTER="false"
export CLUSTER_ADMIN_PASSWORD="<existing-admin-password>"

./compute_init/aws/rosa/setup.sh
```

## Key configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `ROSA_TOKEN` | _(required)_ | Red Hat OCM offline token |
| `CLUSTER_NAME` | `rosa-demo` | Cluster name |
| `REGION` | `us-east-1` | AWS region |
| `CREATE_CLUSTER` | `true` | Create a new cluster vs. connect to existing |
| `HOSTED_CP` | `false` | Hosted Control Plane (HCP). Requires pre-created subnets via `EXTRA_CREATE_ARGS` |
| `COMPUTE_NODES` | `2` | Worker node count |
| `EXTRA_CREATE_ARGS` | _(empty)_ | Extra args passed verbatim to `rosa create cluster` |
| `CLUSTER_ADMIN_PASSWORD` | _(empty)_ | Reuse a known cluster-admin password |
| `READY_TIMEOUT_MIN` | `60` | Minutes to wait for cluster `ready` |

## Kubeconfig handling

Before logging in, the script backs up any existing kubeconfig to
`~/.kube/config.bak.<timestamp>` (or alongside `$KUBECONFIG` if set), then writes
the ROSA context via `oc login`. Launch the cluster UI with:

```bash
k9s
```

## Notes

- Cluster creation typically takes ~30–45 minutes. Follow install logs with
  `rosa logs install -c "$CLUSTER_NAME" --watch`.
- ROSA's service-account JWKS endpoint is not anonymously public. For the
  Secrets Manager K8s demo, use
  `demos/secrets_manager/k8s/setup/k8s/init_aws_rosa.sh` to embed the JWKS.
