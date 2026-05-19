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
| **AWS SPIFFE Integration** | |
| [`QUICKSTART_AWS.md`](QUICKSTART_AWS.md) | **⚡ 5-minute quick start** for AWS SPIFFE testing |
| [`AWS_TESTING.md`](AWS_TESTING.md) | Full AWS SPIFFE testing guide with troubleshooting |
| [`AZURE_TESTING.md`](AZURE_TESTING.md) | Full Azure SPIFFE testing guide with troubleshooting |
| [`LAB_CHECKLIST.md`](LAB_CHECKLIST.md) | Step-by-step lab setup checklist |

## Quick command flow

### Base Demo (Secrets Manager Only)

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

### With Cloud SPIFFE Integration

```bash
cd demos/secrets_manager/swa_k8s

# 1) Configure cloud variables
vi setup/cloud/vars.env
# Set AWS_ACCOUNT_ID/AWS_REGION and/or AZURE_TENANT_ID/AZURE_SUBSCRIPTION_ID/AZURE_REGION

# 2) Set up with one or more clouds
bash setup.sh --aws
bash setup.sh --azure
bash setup.sh --aws --azure

# 3) Validate base demo
bash validate.sh

# 4) Test cloud SPIFFE
source setup/vars.env
kubectl exec -n $NAMESPACE_SWA deployment/giftapp-swa -- \
  curl -sk "https://localhost:8443/csp-test?cloud=aws"
# Expected: {"cloud":"aws","spiffeId":"spiffe://...","content":"hello from cyberark spiffe - aws"}

kubectl exec -n $NAMESPACE_SWA deployment/giftapp-swa -- \
  curl -sk "https://localhost:8443/csp-test?cloud=azure"
# Expected: {"cloud":"azure","spiffeId":"spiffe://...","content":"hello from cyberark spiffe - azure"}
```

## What is SWA?

SWA (Secure Workload Access) is CyberArk's SPIFFE/SPIRE-compatible workload identity platform. It:

1. **Attests** nodes and workloads using Kubernetes projected service account tokens (k8s\_psat)
2. **Issues** short-lived SPIFFE JWT-SVIDs to workloads
3. **Enables** workloads to authenticate to:
   - **Conjur (Secrets Manager)** using JWT-SVIDs — no static API keys, no mounted K8s Secrets
   - **Cloud providers** (AWS, Azure, GCP) using JWT-SVIDs — demonstrates SPIFFE as a universal credential format

## Architecture

### Base Architecture (Secrets Manager)

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

### Extended Architecture (With AWS SPIFFE)

```
┌─────────────────────────────────────────────┐
│  Kubernetes cluster                         │
│                                             │
│  ┌─────────────┐   JWT-SVID (aud=conjur)  ┌───────────────┐
│  │ SWA Agent   │──────────────────────────▶│ giftapp-swa   │
│  │ (DaemonSet) │                           │               │
│  └──────┬──────┘   JWT-SVID (aud=sts)     │  /healthz ────▶ Secrets Manager
│         │ attests  ──────────────────────▶│  /csp-test ───▶ AWS S3
│  ┌──────▼──────┐                           │  (no AWS SDK!)│
│  │ SWA Server  │                           └───────┬───────┘
│  │ (OIDC issuer)│                                   │
│  └─────────────┘                                   │
│                                                     │
└─────────────────────────────────────────────────────┼─────┘
                                                      │
          ┌───────────────────────────────────────────┘
          │
          ▼
  ┌───────────────────┐    JWT-SVID
  │   AWS STS         │◀────────────────  AssumeRoleWithWebIdentity
  │   (OIDC trust)    │    validates via  (audience: sts.amazonaws.com)
  └────────┬──────────┘    SWA OIDC      
           │               discovery     
           ▼                             
  ┌───────────────────┐   temp creds    
  │   Amazon S3       │◀────────────────  SigV4 signed request
  │   (spiffe-demo)   │    test.txt      (no AWS SDK!)
  └───────────────────┘                  
```

## Prerequisites

### Base Demo
- Single-node RKE2 cluster on the demo VM
- `kubectl`, `helm`, `terraform`, and RKE2 `ctr` on the demo VM
- AWS CLI access to the SWA 1.0.3 release bundle in `s3://mis-cybr-demos/pm/swa-release-1-0-3/`
- Docker access on the demo VM to build local GiftApp images, or a container registry with `giftapp-hardcoded` and `giftapp-swa` images pushed
- CyberArk Privilege Cloud tenant + service account (`demos/tenant_vars.sh`)

### Additional for AWS SPIFFE Testing
- AWS account ID and region
- AWS credentials (access key/secret) stored in a CyberArk PAM safe
- EC2 instance with IAM role registered in Conjur (for Summon + authn-iam)
- `summon` and `summon-conjur` installed on the demo VM
- See [`AWS_TESTING.md`](AWS_TESTING.md) for detailed prerequisites
