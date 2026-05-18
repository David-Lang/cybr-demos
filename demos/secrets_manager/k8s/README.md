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
- ESO auto-rotation with sample app (sub-demo)
- direct `curl` authentication and retrieval

### Sub-Demos

| Directory | Pattern | Entry Point |
|---|---|---|
| `eso-reloader/` | ESO 15s refresh + volume/env consumption + Stakater Reloader | `bash eso-reloader/setup.sh` then `bash eso-reloader/demo.sh` |

### `eso-reloader/` notes

- Namespace **`eso-reloader`**. Shares **`k8s-eso`** safe and **`authn-jwt/zg-eso`** with the ESO sub-demo.
- Demonstrates volume mount auto-update vs env vars requiring pod restart (Reloader automates restart).

- External Secrets Operator
- direct `curl` authentication and retrieval

## Standard Names

This demo uses the standard documentation names:

- `demo_setup.md`
- `demo_validation.md`
