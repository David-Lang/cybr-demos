# Secrets Manager — SWA on Kubernetes

This demo shows **CyberArk Secure Workload Access (SWA)** delivering workload identity to a Kubernetes application so it can retrieve secrets from Secrets Manager without any static credentials in its pod spec.

Two versions of the same Flask gift-card app are deployed side-by-side:

| App | Namespace | What it shows |
|-----|-----------|---------------|
| `giftapp-hardcoded` | `$LAB_ID-giftapp-hardcoded` | **Attack surface** — API key and DB password in a mounted K8s Secret |
| `giftapp-swa` | `$LAB_ID-giftapp-swa` | **Defended** — app fetches secrets at runtime via SPIFFE JWT-SVID |

## Documentation index

| Doc | Purpose |
|-----|---------|
| [`demo_setup.md`](demo_setup.md) | Deploy everything (Conjur policy, PAM safe, SWA Server/Agent, apps) |
| [`demo_validation.md`](demo_validation.md) | Validate SWA workload identity and secret retrieval |
| [`validate.sh`](validate.sh) | Non-interactive post-deploy validation |
| [`test_runner.sh`](test_runner.sh) | Full setup plus validation with artifacts |

## Quick command flow

```bash
cd demos/secrets_manager/swa_k8s

# 1) Configure
vi setup/vars.env

# 2) Set up
bash setup.sh

# 3) Validate
bash validate.sh

# 4) Demo
bash demo.sh
```

## What is SWA?

SWA (Secure Workload Access) is CyberArk's SPIFFE/SPIRE-compatible workload identity platform. It:

1. **Attests** nodes and workloads using Kubernetes projected service account tokens (k8s\_psat)
2. **Issues** short-lived SPIFFE JWT-SVIDs to workloads
3. **Enables** workloads to authenticate to Conjur (Secrets Manager) using those SVIDs — no static API keys, no mounted K8s Secrets containing the sensitive values

## Architecture

```
┌─────────────────────────────────────────────┐
│  Kubernetes cluster                         │
│                                             │
│  ┌─────────────┐   SPIFFE JWT-SVID   ┌───────────────┐
│  │ SWA Agent   │──────────────────▶  │ giftapp-swa   │
│  │ (DaemonSet) │   (hostPath socket) │               │
│  └──────┬──────┘                     │  authenticates│
│         │ attests                    │  to Conjur ──▶│──▶ Secrets Manager
│  ┌──────▼──────┐                     │  fetches      │
│  │ SWA Server  │◀─── K8s JWT ──────  │  API key +    │
│  │ (Deployment)│  authenticates to   │  DB password  │
│  └─────────────┘  Secrets Manager    └───────────────┘
│                                             │
│  ┌──────────────────────────────────┐       │
│  │ giftapp-hardcoded (attack)       │       │
│  │  /etc/secrets/GIFTAPP_API_KEY    │       │
│  │  /etc/secrets/DB_PASS   ◀──────K8s Secret
│  └──────────────────────────────────┘       │
└─────────────────────────────────────────────┘
```

## Prerequisites

- Single-node RKE2 cluster on the demo VM
- `kubectl`, `helm`, `terraform`, AWS CLI, and RKE2 `ctr` on the demo VM
- AWS CLI access to the SWA 1.0.3 release bundle in `s3://mis-cybr-demos/pm/swa-release-1-0-3/`
- Docker access on the demo VM to build local GiftApp images, or a container registry with `giftapp-hardcoded` and `giftapp-swa` images pushed
- CyberArk Privilege Cloud tenant + service account (`demos/tenant_vars.sh`)
