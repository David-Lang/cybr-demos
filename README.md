# cybr-demos

Welcome to **cybr-demos** — a collection of hands-on demo scripts for [CyberArk](https://www.cyberark.com/) Secrets Manager, Secrets Hub, and Credential Providers across modern infrastructure platforms.

Whether you are running secrets in Kubernetes, GitHub Actions, GitLab CI, Jenkins, HashiCorp Vault, or AWS Secrets Manager, there is a demo here for you.

| Topic | Location |
|--------|-----------|
| How to write demo docs | [`AGENTS.md`](AGENTS.md), [`demos/demo_md_guidelines.md`](demos/demo_md_guidelines.md) |
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
    ├── demo_md_guidelines.md
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
    └── credential_providers/
        ├── agent_ubuntu/       # CP agent on Linux (incl. access-control scenarios)
        ├── agent_windows/      # CP agent on Windows
        ├── rest_api_ubuntu/    # REST-based retrieval (Ubuntu-oriented scripts)
        └── server_windows/     # Central Credential Provider (Windows)
```

---

## Documentation Conventions

Demo documentation under `demos/` should follow **`AGENTS.md`** and **`demos/demo_md_guidelines.md`**.

In short:

- Use **`demo_setup.md`** for setup and deployment documentation.
- Use **`demo_validation.md`** for post-install validation walkthroughs.
- Prefer linking readers from a short `README.md` into those files instead of duplicating long procedures in multiple places.

The Kubernetes demo is the reference pattern: see `demos/secrets_manager/k8s/README.md` for the documentation index.

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
| `k8s` | Kubernetes cluster (EKS, OCP, or Rancher/RKE2) |
| `github.com` | GitHub repo with Actions enabled |
| `gitlab.com` | GitLab project with CI/CD enabled |
| `jenkins` | Docker (Jenkins runs in a container) |
| `hashi_vault` | Kubernetes cluster + Helm |
| `asm` | AWS account + IAM credentials |
| `agent_ubuntu` | CyberArk CP installer package in S3 |
| `agent_windows` | Windows Server + CyberArk CP installer |
| `server_windows` | Windows Server + Central Credential Provider install path used by the demo |

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

### Secrets Manager Demos

Secrets Manager lets workloads retrieve secrets using their platform identity (Kubernetes service account, GitHub Actions OIDC token, GitLab CI token, etc.) — no hard-coded secrets in the platform configuration.

#### Kubernetes (`demos/secrets_manager/k8s/`)

**What it shows:** A Kubernetes workload authenticates to CyberArk using its service account JWT (OIDC) and retrieves a secret without embedded static credentials.

**Supported clusters:** AWS EKS, OpenShift (OCP), Rancher/RKE2

**Where to read:** Start at `demos/secrets_manager/k8s/README.md`, then follow **`demo_setup.md`** → **`demo_validation.md`** → **`kubectl_commands.md`** (and `aws_eks.md` if you need EKS helpers).

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

**What it shows:** A Jenkins pipeline retrieves secrets using the [Conjur Secrets Plugin](https://plugins.jenkins.io/conjur-secrets/), with context-aware access tied to the Jenkins job.

```bash
cd demos/secrets_manager/jenkins
vi setup/vars.env
bash setup.sh
bash demo.sh
```

> After `setup.sh`, you may need to finish plugin configuration in the Jenkins UI. See `demos/secrets_manager/jenkins/README.md` for detailed steps.

**Clean up:**

```bash
bash setup/jenkins/remove.sh
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
