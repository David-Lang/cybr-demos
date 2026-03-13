# Kubernetes Demo Deployment And Setup

This guide covers how this demo is deployed and prepared in the repo.

This is the deployment path for the Rancher-based lab environment. The validation and runtime patterns demonstrated by the workloads are standard Kubernetes patterns, but the automation in this repo is Rancher-first.

## Purpose

The setup flow does four things:

1. Initializes Kubernetes access for the Rancher lab cluster.
2. Creates or prepares the CyberArk safe and demo account content.
3. Configures the Secrets Manager JWT authenticator and workload policy.
4. Deploys the Kubernetes resources and External Secrets Operator.

## Main Entry Point

Run the demo setup from the demo directory:

```bash
cd demos/secrets_manager/k8s
./setup.sh
```

The main setup script is:

- `setup.sh`

That wrapper runs these main steps:

- `setup/k8s/init_rancher.sh`
- `setup/vault/setup.sh`
- `setup/sm/setup.sh`
- `setup/k8s/setup.sh`

## Deployment Context

This repo’s default deployment path is Rancher/RKE2.

That means:

- `setup.sh` currently assumes the Rancher init path
- the local cluster bootstrap is done through `init_rancher.sh`
- `kubectl` access is expected to come from that Rancher-based environment

The use cases deployed after that are still standard Kubernetes resources:

- Deployments
- Secrets
- ConfigMaps
- ServiceAccounts
- RBAC
- External Secrets Operator resources

## Required Environment

The demo relies on tenant and workload variables from:

- `setup/vars.env`
- shared tenant environment loaded by the setup scripts

Key values include:

- `SM_SERVICE_NAME`
- `SAFE_NAME`
- `SM_SECRET_1_ID`
- `SM_SECRET_2_ID`
- `K8S_SERVICE_ACCOUNT`
- `K8S_TYPE`

## What `setup.sh` Does

The wrapper script:

- validates the demo path
- checks that the required step scripts exist
- makes the step scripts executable
- adds Rancher `kubectl` paths when needed
- runs the setup stages in order

If `kubectl` is available, it also performs a basic cluster check with:

```bash
kubectl get nodes
```

## Kubernetes Deployment Step

The Kubernetes deployment stage is handled by:

- `setup/k8s/setup.sh`

That script:

- loads `setup/vars.env`
- installs or upgrades External Secrets Operator
- retrieves the Secrets Manager certificate
- deploys the Helm chart `setup/k8s/charts/poc-sm`

## Helm Chart Contents

The chart installs the demo namespace and shared config, plus the individual use cases:

- K8s Secrets
- K8s Secrets FetchAll
- Push To File
- Push To File FetchAll
- External Secrets Operator integration
- helper pod for direct `curl` testing

The main chart templates are:

- `setup/k8s/charts/poc-sm/templates/namespace.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-k8s-secrets.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-k8s-secrets-fetch-all.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-push-to-file.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-push-to-file-fetch-all.yaml`
- `setup/k8s/charts/poc-sm/templates/demo-eso-sm.yaml`
- `setup/k8s/charts/poc-sm/templates/alpine-curl.yaml`

## Secrets Manager Setup Step

The Secrets Manager configuration is handled by:

- `setup/sm/setup.sh`

That step:

- loads tenant credentials and demo variables
- configures the JWT authenticator
- applies workload policy
- grants workload access to the safe

## Vault Setup Step

The safe and account preparation is handled by:

- `setup/vault/setup.sh`

That stage creates the safe-backed content used by the demo secret retrieval patterns.

## Alternative Cluster Helpers

The repo contains helper scripts for other cluster types:

- `setup/k8s/init_eks.sh`
- `setup/k8s/init_ocp.sh`

Those are useful reference points, but the primary setup path for this demo is Rancher.

## After Setup

After deployment completes, use these docs:

- `demo_validation.md` for validation walkthrough
- `kubectl_commands.md` for command reference
- `aws_eks.md` for AWS EKS helper commands

## Troubleshooting Setup

If setup fails, check these first:

- `kubectl` resolves correctly
- the active cluster context is correct
- tenant variables are available
- the CyberArk safe and authenticator steps completed successfully
- Helm can reach the cluster and install resources

Useful checks:

```bash
kubectl get nodes
kubectl get namespaces
helm list -A
kubectl get pods -n external-secrets
```
