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
- direct `curl` authentication and retrieval

## Standard Names

This demo uses the standard documentation names:

- `demo_setup.md`
- `demo_validation.md`
