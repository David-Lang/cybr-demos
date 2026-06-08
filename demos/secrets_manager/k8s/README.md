# Kubernetes Demo Docs

This directory contains a Kubernetes Secrets Manager demo deployed through the Rancher-based lab setup in this repo.

The deployment automation is Rancher-first. The use-case patterns demonstrated by the workloads are standard Kubernetes patterns and are intended to be conceptually valid on other conformant Kubernetes platforms, including OpenShift.

## Documentation Index

- `demo_setup.md`
  - how the demo is deployed and configured in this repo
  - setup flow, Helm deployment, and supporting scripts

- `demo_validation.md`
  - post-install walkthrough for validating and understanding the deployed use cases
  - focuses on runtime behavior and CyberArk functionality

- `kubectl_commands.md`
  - command reference for validating the demo after deployment

- `aws_eks.md`
  - AWS EKS helper commands and context setup notes

## Official Documentation Links

Current official CyberArk references:

- [Secrets Manager SaaS Documentation](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/resources/_topnav/cc_home.htm)
- [Secrets Manager Authentication Methods](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/operations/authn/authn-lp.htm)

Official repository reference for the Kubernetes provider patterns used in this demo:

- [CyberArk Secrets Provider for Kubernetes](https://github.com/cyberark/secrets-provider-for-k8s)
- [External Secrets Operator Documentation](https://external-secrets.io/latest/)

## Recommended Reading Order

1. `demo_setup.md`
2. `demo_validation.md`
3. `kubectl_commands.md`

Use `aws_eks.md` only if you need the EKS helper content.

## Demo Scope

This demo includes these main patterns:

- K8s Secrets
- K8s Secrets FetchAll
- Push To File
- Push To File FetchAll
- External Secrets Operator
- ESO Auto-Rotation
- Secrets Provider for K8s (sidecar)
- Secure Workload Access (SPIFFE JWT-SVID)
- direct `curl` authentication and retrieval

### Sub-Demos

| Directory | Pattern | Entry Point |
|---|---|---|
| `eso/` | External Secrets Operator — general Conjur Cloud walkthrough (`refreshInterval: 15s`) | `bash eso/demo.sh` |
| `eso-reloader/` | ESO + Stakater Reloader — same 15s refresh; sample app (volume + env vars) and rolling restart on secret change | `bash eso-reloader/demo.sh` |
| `sidecar/` | CyberArk Secrets Provider for K8s — sidecar mode, `k8s_secrets` destination, 15s refresh (same `k8s-eso` safe as ESO) | `bash sidecar/setup.sh` then `bash sidecar/demo.sh` |
| `swa-minikube/` | Secure Workload Access — SPIFFE workload identity on **minikube** (official SWA release + in-cluster Server/Agent), JWT-SVID via `authn-jwt/secureWorkloadAccess` | `bash swa-minikube/go.sh` then `bash swa-minikube/demo.sh` |

**Not this folder:** upstream [`../swa_k8s/`](../swa_k8s/) is a separate Rancher/giftapp-based SWA walkthrough. Use **`swa-minikube/`** for the minikube + Conjur Cloud SaaS flow built here.

### `eso/` manifests — namespace and refresh

- **`secretstore.yaml`** and **`externalsecret.yaml`** set `metadata.namespace: external-secrets`. That way a bare `kubectl apply -f demos/secrets_manager/k8s/eso/<file>.yaml` updates the demo in the right namespace. Without a namespace in the manifest, the same command applies to **`default`** and creates a broken duplicate ExternalSecret (wrong SecretStore reference).
- **`refreshInterval`** is **`15s`** on the ExternalSecret — same cadence as **`eso-reloader/`** so both demos behave consistently during rotation walkthroughs.

**Re-applying SecretStore:** The SecretStore *spec* (Conjur URL, JWT) did not change for the 15s / namespace edits — only metadata (namespace) was added to the file. If **`kubectl get secretstore -n external-secrets conjur`** is already **Valid**, you do **not** need to re-apply. Re-apply only when bootstrapping a new cluster or if you intentionally changed URL/auth in the YAML.

### `eso-reloader/` (renamed from `eso-rotation`)

The folder **`eso-rotation`** was renamed to **`eso-reloader`** to reflect the Stakater Reloader story (auto rolling restart when mounted secrets change). Kubernetes uses namespace **`eso-reloader`**, ServiceAccount **`eso-reloader-sa`**, and Conjur policy host IDs **`system:serviceaccount:eso-reloader:eso-reloader-sa`**. If you had the old namespace deployed, remove it and run **`eso-reloader/setup.sh`** after loading tenant env (see **`eso-reloader/demo_setup.md`**).

Helm chart **`setup/k8s/charts/poc-sm/templates/demo-eso-sm.yaml`** uses the same **`refreshInterval: 15s`** for packaged ESO demos.

## Editor / YAML lint (Conjur policy)

Workspace **`.vscode/settings.json`** includes **`yaml.customTags`** for Conjur policy tags (`!policy`, `!host`, `!grant`, …) so the YAML language server does not report “Unresolved tag” on demo policy files.

## Standard Names

This demo uses the standard documentation names:

- `demo_setup.md`
- `demo_validation.md`
