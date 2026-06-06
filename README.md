# cybr-demos

Welcome to **cybr-demos** — a collection of hands-on demo scripts for [CyberArk](https://www.cyberark.com/) Machine Identity, Secrets Manager, Secrets Hub, and Credential Providers across modern infrastructure platforms.

Whether you are running secrets in Kubernetes, GitHub Actions, GitLab CI, Jenkins, HashiCorp Vault, or AWS Secrets Manager, there is a demo here for you.

| Topic | Location |
|--------|-----------|
| How to write demo docs | [`AGENTS.md`](AGENTS.md), [`demos/guidelines/demo_md_guidelines.md`](demos/guidelines/demo_md_guidelines.md) |
| MCP / lab automation docs | [`mcp-server/README.md`](mcp-server/README.md) |
| Ubuntu / Windows VM setup | [`compute_init/ubuntu/setup.sh`](compute_init/ubuntu/setup.sh), [`compute_init/windows/setup.ps1`](compute_init/windows/setup.ps1) |
| One-shot clone + Ubuntu init | [`init_cybr_demos.sh`](init_cybr_demos.sh) |
| Bash lint (local + CI on `main`) | [`.shellcheckrc`](.shellcheckrc), [`.github/workflows/shellcheck.yml`](.github/workflows/shellcheck.yml) |

---

## Table of Contents

- [What Is This Repo?](#what-is-this-repo)
- [Repo Structure](#repo-structure)
- [Documentation Conventions](#documentation-conventions)
- [MCP Server (Optional)](#mcp-server-optional)
- [Before You Start](#before-you-start)
- [Configuration](#configuration)
- [Demo Walk-Throughs](#demo-walk-throughs)
  - [Machine Identity Portfolio](#machine-identity-portfolio-demo)
  - [Secure AI Agents](#secure-ai-agents-demos)
  - [Secrets Manager](#secrets-manager-demos)
  - [Secrets Hub](#secrets-hub-demos)
  - [Credential Providers](#credential-provider-demos)
- [Environment Setup](#environment-setup)
- [Code Quality](#code-quality)

---

## What Is This Repo?

This repo gives you runnable, end-to-end scripts for demonstrating how CyberArk products integrate with real-world platforms. Each demo is self-contained and follows the same general pattern:

1. **Configure** — fill in your tenant details in `demos/tenant_vars.sh` and any demo-specific `setup/vars.env`
2. **Set up** — run `setup.sh` (or the setup entry script for that demo) to provision backends, policies, and platform connectors
3. **Demo** — run `demo.sh` or `demo.ps1` to show the integration working live

The scripts are written in Bash (Linux/Ubuntu) and PowerShell (Windows) and are designed to be run from a provisioned demo VM.

---

## Repo Structure

```
cybr-demos/
├── AGENTS.md               # How to write/update demo docs under demos/
├── init_cybr_demos.sh      # Optional: clone this repo + run Ubuntu compute_init
├── compute_init/           # VM provisioning scripts (Ubuntu + Windows)
│   ├── ubuntu/             #   docker, kubectl, helm, terraform, awscli, summon, etc.
│   └── windows/            #   Chocolatey, IIS, PowerShell 7, AWS tools, etc.
├── mcp-server/             # Optional MCP tooling + long-form operational docs
│
└── demos/
    ├── setup_env.sh        # Master bootstrap — sources shared helpers + tenant vars
    ├── tenant_vars.sh      # YOUR tenant credentials + LAB_ID (edit this first)
    ├── guidelines/
    │   ├── demo_md_guidelines.md
    │   ├── video_demo_guidelines.md
    │   └── video_recording_assets_guidelines.md
    ├── utility/ubuntu/     # Shared helpers (Identity, Conjur, Privilege Cloud, templates, AWS)
    │
    ├── secrets_manager/    # Demos: retrieve secrets from CyberArk Secrets Manager
    │   ├── k8s/            #   Kubernetes workload identity (OIDC JWT)
    │   ├── github.com/     #   GitHub Actions OIDC integration
    │   ├── gitlab.com/     #   GitLab CI OIDC integration
    │   ├── jenkins/        #   Jenkins Conjur plugin
    │   ├── summon_ubuntu/  #   summon CLI on Linux
    │   └── summon_powershell/  # summon-style flow on Windows
    │
    ├── secrets_hub/        # Demos: Secrets Hub across backends
    │   ├── hashi_vault/    #   HashiCorp Vault on Kubernetes
    │   ├── asm/            #   AWS Secrets Manager
    │   └── aws_cli/        #   Direct AWS CLI retrieval
    │
    ├── machine_identity/   # Demos: Full machine identity portfolio
    │   └── portfolio_workflow/  # End-to-end unified demo:
    │       ├── setup/           #   vault, sm, secrets_hub, sia, vcert, cert_manager, sai
    │       └── demo.sh          #   ISPSS → Conjur → 3 cert options → Secrets Hub → SIA → SCA → SAI
    │
    ├── secure_ai_agents/   # Demos: AI agent identity & vaulted secrets
    │   └── spiffe_conjur/       # SPIFFE/SPIRE → Conjur Cloud authn-jwt:
    │       ├── setup/           #   spire, workloads, oidc (cloudflared), conjur
    │       └── demo.sh          #   BEFORE (key in env) → SPIRE attest → JWT-SVID → vaulted secret → live revoke
    │
    └── credential_providers/
        ├── agent_ubuntu/       # CP agent on Linux (incl. access-control scenarios)
        ├── agent_windows/      # CP agent on Windows
        ├── rest_api_ubuntu/    # REST-based retrieval (Ubuntu-oriented scripts)
        └── server_windows/     # Central Credential Provider (Windows)
```

---

## Documentation Conventions

Demo documentation under `demos/` should follow **`AGENTS.md`** and **`demos/guidelines/demo_md_guidelines.md`**.

In short:

- Use **`demo_setup.md`** for setup and deployment documentation.
- Use **`demo_validation.md`** for post-install validation walkthroughs.
- Prefer linking readers from a short `README.md` into those files instead of duplicating long procedures in multiple places.

The Kubernetes demo is the reference pattern: see `demos/secrets_manager/k8s/README.md` for the documentation index, **`eso/`** / **`eso-reloader/`** sub-demos, and related operational notes.

---

## MCP Server (Optional)

The `mcp-server/` directory contains an optional MCP-oriented workflow and extensive supporting markdown (quickstarts, tool contracts, upgrade notes). If you are using this repo as an orchestration layer for lab automation or assistant-driven workflows, start with `mcp-server/README.md`.

---

## Before You Start

### Pick Your Demo VM

All Bash demos run on Ubuntu. On a fresh VM, run the Ubuntu provisioning script once:

```bash
cd compute_init/ubuntu
bash setup.sh
```

For Windows-based demos (Credential Providers), run `compute_init/windows/setup.ps1` in an elevated PowerShell session.

### Optional: clone + provision in one step

On a lab VM you can use the root script (adjust `CYBR_DEMOS_PATH` / user as needed):

```bash
export CYBR_DEMOS_PATH=/home/ubuntu/cybr-demos
bash init_cybr_demos.sh
```

### Prerequisites by Demo

| Demo | Requires |
|------|----------|
| All | CyberArk Privilege Cloud tenant + service account |
| `portfolio_workflow` | ISPSS service account with Conjur Admin, Secrets Hub Admin, DpaAdmin roles. Optional: CyberArk Certificate Manager (VCert), K8s cluster (cert-manager), AWS account (Secrets Hub), SSH target (SIA) |
| `k8s` | Kubernetes cluster (EKS, OCP, or Rancher/RKE2) |
| `github.com` | GitHub repo with Actions enabled |
| `gitlab.com` | GitLab project with CI/CD enabled |
| `jenkins` | Docker (Jenkins runs in a container). Optional Edge mode also needs the Conjur Cloud Edge image + an Edge instance from the Secrets Manager UI. |
| `hashi_vault` | Kubernetes cluster + Helm |
| `asm` | AWS account + IAM credentials |
| `agent_ubuntu` | CyberArk CP installer package in S3 |
| `agent_windows` | Windows Server + CyberArk CP installer |
| `server_windows` | Windows Server + Central Credential Provider install path used by the demo |
| `spiffe_conjur` | Local Docker + minikube + cloudflared. Conjur Cloud service user with `Authn_Admins` (or `Conjur_Cloud_Admins`) role. |

---

## Configuration

### Step 1 — Tenant credentials and lab identity

Edit `demos/tenant_vars.sh` with your CyberArk cloud environment details:

```bash
LAB_ID="lab01"                             # unique label for generated safe names in shared labs
TENANT_ID="aabbcc"                        # your tenant short ID
TENANT_SUBDOMAIN="mycompany"              # subdomain for your Privilege Cloud tenant
CLIENT_ID="your-service-account@cyberark" # service account username
CLIENT_SECRET="your-client-secret"        # service account credential
INSTALLER_USR="installer-user"            # installer account (CP demos only)
INSTALLER_PWD="installer-password"
```

> **Never commit real credentials.** `tenant_vars.sh` is your local config — keep it out of source control.

### Step 2 — Demo-specific variables

Each demo has its own `setup/vars.env`. Open it before running setup and fill in platform-specific values (Kubernetes namespace, GitHub repo name, Vault namespace, AWS region, etc.). Each file is annotated with comments explaining the variables.

### Step 3 — Repo path

Most scripts expect **`CYBR_DEMOS_PATH`** to point at the root of this repository:

```bash
export CYBR_DEMOS_PATH="/path/to/cybr-demos"
```

---

## Demo Walk-Throughs

### Machine Identity Portfolio Demo

A single end-to-end workflow demonstrating the full CyberArk machine identity portfolio. This demo walks through all nine components in sequence, showing how they share a unified identity platform.

#### Portfolio Workflow (`demos/machine_identity/portfolio_workflow/`)

**What it shows:** A microservice authenticates to ISPSS, retrieves secrets from Conjur Cloud, obtains TLS certificates three different ways (Conjur PKI, VCert SDK, cert-manager), verifies Secrets Hub sync, inspects JIT infrastructure and cloud access, and demonstrates AI agent identity lifecycle with AI Gateway MCP server inventory — all in one interactive walkthrough.

| Step | Component | Capability |
|------|-----------|------------|
| 1 | ISPSS Platform Auth | OAuth2 service account token |
| 2 | Conjur Cloud | Workload OIDC authentication |
| 3 | Conjur Cloud | Application secret retrieval |
| 4a | Conjur Cloud PKI | Ephemeral short-lived workload certs |
| 4b | VCert Python SDK | Full lifecycle: request → retrieve → renew → revoke |
| 4c | cert-manager + CyberArk Issuer | K8s-native auto-provisioning and renewal |
| 5 | Secrets Hub | PAM → cloud-native secret sync verification |
| 6 | Secure Infrastructure Access (SIA) | JIT SSH certificates |
| 7 | Secure Cloud Access (SCA) | JIT cloud role elevation |
| 8 | Secure AI Agents | Agentic identity lifecycle + AI Gateway MCP inventory |

**Prerequisites:** CyberArk ISPSS tenant with service account. Certificate, Secrets Hub, SIA, and SAI stages are optional — they skip cleanly or fall back to demo mode if not configured.

| Optional Feature | Requires |
|---|---|
| VCert SDK (live) | `VCERT_API_KEY` (SaaS) or `VCERT_TPP_*` (Self-Hosted) |
| cert-manager (live) | Kubernetes cluster + `kubectl` + `helm` |
| Secrets Hub | `SH_AWS_ACCOUNT_ID` + IAM role |
| SIA | `SIA_TARGET_HOST` |
| Secure AI Agents | `SAI_AGENT_NAME` + `Secure AI Admins` or `Secure AI Builders` role |

```bash
cd demos/machine_identity/portfolio_workflow

# 1) Configure (optional: fill VCERT_*, SH_AWS_*, SIA_* vars for full demo)
vi setup/vars.env

# 2) Set up
bash setup.sh

# 3) Demo (interactive — press ENTER between steps)
bash demo.sh
```

**Where to read:** `demo_setup.md` → `demo_validation.md`

---

### Secure AI Agents Demos

#### SPIFFE / SPIRE → Conjur Cloud (`demos/secure_ai_agents/spiffe_conjur/`)

**What it shows:** An AI agent pod authenticates to **CyberArk Conjur Cloud**
using a SPIFFE JWT-SVID (`authn-jwt`) and retrieves a vaulted secret. The
demo is built as a side-by-side: a `vulnerable-agent` pod with a hardcoded
API key in env, and an `attested-agent` pod with zero credentials in its
spec. A live revocation step (delete one `ClusterSPIFFEID`) cuts both SPIRE
and Conjur access in seconds.

**What you see:**

| Step | What happens |
|---|---|
| 1 | Inspect the BEFORE pod — key in pod spec, etcd, and env |
| 2 | Architecture: K8s Pod → SPIRE → JWT-SVID → Conjur authn-jwt → vaulted secret |
| 3 | SPIRE attests the workload, mints an X.509 SVID for the pod |
| 4 | Fetch the JWT-SVID, decode payload, see `sub` claim that maps to a Conjur host |
| 5 | Live POST: agent presents JWT-SVID to Conjur Cloud, receives 8-min access token |
| 6 | Use access token to fetch the vaulted secret — no env, no Secret, no etcd |
| 7 | Live revoke: delete one ClusterSPIFFEID, both SPIRE and Conjur reject within seconds |
| 8 | Side-by-side comparison + portfolio positioning (Conjur, Secrets Hub, Discovery, AI Gateway) |

**Prerequisites:** local Docker, `minikube`, `kubectl`, `helm`, `cloudflared`,
`envsubst`. CyberArk Conjur Cloud tenant with a service user that has
`Authn_Admins` or `Conjur_Cloud_Admins`.

```bash
cd demos/secure_ai_agents/spiffe_conjur
vi setup/vars.env       # adjust LAB_ID-derived defaults if needed
./setup.sh              # SPIRE on minikube → workloads → cloudflared → Conjur authn-jwt
./demo.sh               # interactive ~12-min walkthrough
./cleanup.sh            # tears down minikube + Conjur policies
```

**Where to read:** `demo_setup.md` → `demo_validation.md`

---

### Secrets Manager Demos

Secrets Manager lets workloads retrieve secrets using their platform identity (Kubernetes service account, GitHub Actions OIDC token, GitLab CI token, etc.) — no hard-coded secrets in the platform configuration.

#### Kubernetes (`demos/secrets_manager/k8s/`)

**What it shows:** A Kubernetes workload authenticates to CyberArk using its service account JWT (OIDC) and retrieves a secret without embedded static credentials.

**Supported clusters:** AWS EKS, OpenShift (OCP), Rancher/RKE2

**Where to read:** Start at `demos/secrets_manager/k8s/README.md`, then follow **`demo_setup.md`** → **`demo_validation.md`** → **`kubectl_commands.md`** (and `aws_eks.md` if you need EKS helpers). The same `k8s/README.md` summarizes the **`eso/`** and **`eso-reloader/`** sub-demos (15s ESO refresh, Stakater Reloader, manifest namespaces, and the **`eso-rotation` → `eso-reloader`** folder rename).

**Quick command flow:**

```bash
cd demos/secrets_manager/k8s

# 1) Configure
vi setup/vars.env

# 2) Set up
bash setup.sh

# 3) Demo / explore
bash demo.sh
```

#### SWA on Kubernetes (`demos/secrets_manager/swa_k8s/`)

**What it shows:** A side-by-side attack/defend Kubernetes demo where `giftapp-hardcoded` exposes API and database credentials through Kubernetes Secrets, while `giftapp-swa` retrieves the same secrets at runtime with a SPIFFE JWT-SVID from CyberArk Secure Workload Access.

**Supported cluster path:** Single-node Rancher/RKE2 lab VM.

**Where to read:** Start at `demos/secrets_manager/swa_k8s/README.md`, then follow **`demo_setup.md`** → **`demo_validation.md`**.

**Quick command flow:**

```bash
cd demos/secrets_manager/swa_k8s

# 1) Configure
vi setup/vars.env

# 2) Set up
bash setup.sh

# 3) Validate
bash validate.sh

# 4) Demo / explore
bash demo.sh
```

For unattended setup plus validation with captured logs:

```bash
bash test_runner.sh
```

#### GitHub Actions (`demos/secrets_manager/github.com/`)

**What it shows:** A GitHub Actions workflow uses OIDC to authenticate to CyberArk and retrieve a secret during CI — without storing CyberArk credentials in GitHub.

```bash
cd demos/secrets_manager/github.com
vi setup/vars.env
bash setup.sh
bash demo.sh
```

#### GitLab CI (`demos/secrets_manager/gitlab.com/`)

**What it shows:** Same pattern as GitHub Actions, for GitLab CI pipelines.

```bash
cd demos/secrets_manager/gitlab.com
vi setup/vars.env
bash setup.sh
bash demo.sh
```

#### Jenkins (`demos/secrets_manager/jenkins/`)

**What it shows:** A Jenkins pipeline retrieves credentials at run time from CyberArk Secrets Manager via the [Conjur Secrets Plugin](https://plugins.jenkins.io/conjur-credentials/), authenticating with a short-lived JWT (`authn-jwt`) where each pipeline job's `jenkins_full_name` is its own Conjur workload identity. No static API key lives in Jenkins.

Two architectures, switchable via `CONJUR_AUTH_TARGET` + `JWT_TRUST_MODE` in `setup/vars.env`:

| Mode | Story |
|------|-------|
| **cloud** (default) | Jenkins authenticates directly to Conjur Cloud SaaS. Signature trust via a JWKS mirrored into the `public-keys` variable — works on a laptop with no inbound network. |
| **edge** | Jenkins authenticates against a local **Conjur Cloud Edge** container on the same Docker host. Edge replicates policy + secrets from Conjur Cloud and validates JWTs locally — the auth + secret-read path never leaves the host. For restricted-egress, latency-sensitive, or regulated environments. |

```bash
cd demos/secrets_manager/jenkins
cp setup/vars.env.example setup/vars.env
cp ../../tenant_vars.local.sh.example ../../tenant_vars.local.sh   # TENANT_ID, CLIENT_*
bash go.sh
bash ready_check.sh
bash demo.sh
```

> Presenter UI: http://127.0.0.1:8081/job/global-credentials-demo/ — see `demo_validation.md`.
> Edge bring-up: see `setup/edge/README.md`.

**Clean up:**

```bash
bash remove.sh
```

#### Summon on Linux (`demos/secrets_manager/summon_ubuntu/`)

**What it shows:** Inject a secret from Conjur into a command environment using the `summon` CLI.

```bash
cd demos/secrets_manager/summon_ubuntu
vi setup/vars.env   # as needed
bash demo.sh
```

#### Summon on Windows (`demos/secrets_manager/summon_powershell/`)

**What it shows:** PowerShell-oriented secret injection demo patterns (see that directory’s scripts and `README.md`).

---

### Secrets Hub Demos

Secrets Hub is CyberArk’s service for managing secrets across multiple backends from a single control plane.

#### HashiCorp Vault on Kubernetes (`demos/secrets_hub/hashi_vault/`)

```bash
cd demos/secrets_hub/hashi_vault
vi setup/vars.env
bash setup/setup.sh
```

#### AWS Secrets Manager (`demos/secrets_hub/asm/`)

```bash
cd demos/secrets_hub/asm
vi setup/vars.env
bash setup.sh
```

#### AWS CLI direct (`demos/secrets_hub/aws_cli/`)

```bash
cd demos/secrets_hub/aws_cli
bash demo.sh
```

---

### Credential Provider Demos

The CyberArk Credential Provider (CP) retrieves credentials from Privilege Cloud on behalf of applications, with caching and access control enforcement.

#### Linux CP agent (`demos/credential_providers/agent_ubuntu/`)

**What it shows:** An application on Linux retrieves a credential via the local CP agent. The demo includes access-control scenarios (impostor / tamper cases).

```bash
cd demos/credential_providers/agent_ubuntu
vi setup/vars.env
bash setup.sh
bash demo.sh
bash app1.sh
bash app1_imposter.sh
bash app1_modified.sh
```

#### Windows CP agent (`demos/credential_providers/agent_windows/`)

```powershell
cd demos/credential_providers/agent_windows/setup
.\install_cp.ps1
.\demo.ps1
```

#### REST API (`demos/credential_providers/rest_api_ubuntu/`)

**What it shows:** Application-style retrieval via REST (see `README.md` in that folder for prerequisites and flow).

```bash
cd demos/credential_providers/rest_api_ubuntu
vi setup/vars.env
bash setup.sh
bash demo.sh
```

#### Central Credential Provider (`demos/credential_providers/server_windows/`)

**What it shows:** Centralized HTTPS retrieval without a local agent install on every consumer (Windows-oriented demo entry points).

```powershell
cd demos/credential_providers/server_windows
.\setup\setup.ps1
.\demo.ps1
```

---

## Environment Setup

### Shared bootstrap

`demos/setup_env.sh` loads `demos/tenant_vars.sh` and then sources shared helpers from `demos/utility/ubuntu/`:

| File | Purpose |
|------|---------|
| `identity_functions.sh` | Identity / OAuth helpers |
| `conjur_functions.sh` | Conjur API helpers |
| `privilege_functions.sh` | Privilege Cloud / vault-style platform helpers |
| `template_functions.sh` | Template rendering helpers |
| `aws_functions.sh` | AWS helper utilities |

The legacy filename `priviledge_functions.sh` remains as a thin shim for older scripts and docs; new work should use `privilege_functions.sh`.

Supporting output/formatting helpers also live under `demos/utility/ubuntu/` (for example `ansi_colors.sh`, `demo_utility.sh`).

---

## Code Quality

Shell scripts in `demos/`, `compute_init/`, and selected root/bootstrap paths are linted with [ShellCheck](https://www.shellcheck.net/).

- **Local:** use [`.shellcheckrc`](.shellcheckrc) at the repo root (severity and sourcing hints).
- **CI:** pushes and pull requests to `main` run [`.github/workflows/shellcheck.yml`](.github/workflows/shellcheck.yml).

Example local check while iterating:

```bash
shellcheck demos/**/*.sh compute_init/**/*.sh
```
