# Machine Identity Portfolio — Demo Setup

## Overview

This demo deploys resources across the CyberArk Identity Security Platform to demonstrate the full machine identity portfolio in a single workflow. It creates a Privilege Cloud safe with demo accounts, configures Conjur Cloud workload identity, optionally sets up Secrets Hub sync, SIA targets, VCert SDK, and cert-manager with a CyberArk Issuer.

## Main Entry Point

```bash
./setup.sh
```

## Prerequisites

- `tenant_vars.sh` configured with valid ISPSS credentials
- `setup_env.sh` sourced (setup.sh handles this automatically)
- `curl` and `jq` installed
- ISPSS service account with roles: Privilege Cloud Admin, Conjur Admin, Secrets Hub Admin, DpaAdmin

### Additional prerequisites by stage

| Stage | Requires |
|---|---|
| VCert SDK (Stage 5) | `python3`, `pip3 install vcert` |
| cert-manager (Stage 6) | `kubectl`, `helm`, access to a Kubernetes cluster |

## Environment Variables

All demo-specific configuration is in `setup/vars.env`. Tenant credentials come from `demos/tenant_vars.sh`.

### Core (required)

| Variable | Purpose |
|---|---|
| `LAB_ID` | Lab identifier for unique naming |

### Secrets Hub (optional — skips if empty)

| Variable | Purpose |
|---|---|
| `SH_AWS_ACCOUNT_ID` | AWS account for Secrets Hub target |
| `SH_AWS_REGION` | AWS region for target store |
| `SH_AWS_ROLE_NAME` | IAM role for Secrets Hub |

### SIA (optional — skips if empty)

| Variable | Purpose |
|---|---|
| `SIA_TARGET_HOST` | Target host for SIA demo |
| `SIA_TARGET_USER` | SSH user on SIA target |

### VCert SDK (optional — uses fake mode if empty)

| Variable | Purpose |
|---|---|
| `VCERT_API_KEY` | CyberArk Certificate Manager SaaS API key |
| `VCERT_TPP_URL` | CyberArk Certificate Manager Self-Hosted URL |
| `VCERT_TPP_USER` | TPP username (alternative to access token) |
| `VCERT_TPP_PASSWORD` | TPP password |
| `VCERT_TPP_ACCESS_TOKEN` | TPP access token (alternative to user/pass) |
| `VCERT_ZONE` | Certificate policy zone |
| `VCERT_COMMON_NAME` | Certificate common name |
| `VCERT_SAN_DNS` | Comma-separated SAN DNS names |

### cert-manager (optional — uses self-signed issuer if no CyberArk creds)

| Variable | Purpose |
|---|---|
| `CM_NAMESPACE` | K8s namespace for cert-manager demo resources |
| `CM_CERT_COMMON_NAME` | Certificate common name |
| `CM_CERT_SECRET_NAME` | K8s Secret name for the issued cert |

cert-manager uses the same `VCERT_API_KEY` or `VCERT_TPP_*` credentials to configure the CyberArk Issuer.

## Setup Stages

### Stage 1: Vault (`setup/vault/setup.sh`)

- Creates safe `{LAB_ID}-machine-identity`
- Adds Secrets Hub and Conjur Sync read members
- Creates three demo accounts: DB host, DB user, API key

### Stage 2: Secrets Manager (`setup/sm/setup.sh`)

- Authenticates to Conjur Cloud via OIDC
- Waits for Vault Synchronizer to sync the safe
- Applies workload identity policy with host and consumer group
- Rotates workload API key

### Stage 3: Secrets Hub (`setup/secrets_hub/setup.sh`)

- Skipped if `SH_AWS_ACCOUNT_ID` is empty
- Creates AWS Secrets Manager target store
- Looks up PAM source store
- Creates sync policy filtering on the demo safe

### Stage 4: SIA (`setup/sia/setup.sh`)

- Skipped if `SIA_TARGET_HOST` is empty
- Creates SSH connection target in SIA

### Stage 5: VCert SDK (`setup/vcert/setup.sh`)

- Verifies python3 is installed
- Installs vcert SDK if missing
- Falls back to fake mode if no CyberArk Certificate Manager credentials are set

### Stage 6: cert-manager (`setup/cert_manager/setup.sh`)

- Skipped if no Kubernetes cluster is available
- Installs cert-manager via Helm
- Creates CyberArk credential Secret (SaaS API key or TPP token/user)
- Deploys CyberArk Issuer (SaaS, Self-Hosted, or self-signed fallback)
- Requests a Certificate resource and waits for issuance

### Stage 7: Secure AI Agents (`setup/sai/setup.sh`)

- Skipped if `SAI_AGENT_NAME` is empty
- Checks for existing agent registration (idempotent)
- Registers a new AI agent (type: COPILOT, CLAUDE, or CUSTOM)
- Returns `clientId`, `clientSecret`, and `gatewayUrl`
- Attempts activation (PENDING_CONNECTION → ACTIVE)
- Optionally registers SIA DB MCP server in the AI Gateway (if `SAI_AIGW_SIA_MCP_URL` is set)

### Secure AI Agents (optional — skips if empty)

| Variable | Purpose |
|---|---|
| `SAI_AGENT_NAME` | Agent display name |
| `SAI_AGENT_TYPE` | `COPILOT`, `CLAUDE`, or `CUSTOM` |
| `SAI_AGENT_DESCRIPTION` | Agent description |
| `SAI_CALLBACK_URL` | OAuth redirect callback URL |
| `SAI_AIGW_SIA_MCP_URL` | SIA DB MCP upstream URL for AI Gateway registration |

### Secure AI Agents — Required Roles

| Role | Purpose |
|---|---|
| `Secure AI Admins` | Full SAI administration |
| `Secure AI Builders` | Agent registration and gateway configuration |

> If SAI was previously installed on the tenant and is missing the `Secure AI Builders` role, either reinstall SAI or create the role via `POST /roles/storerole`. See [`setup/sai/dp_tenant_preparations.md`](setup/sai/dp_tenant_preparations.md) for full tenant prep steps including SIA MCP creation via API and known issues. For the full SAI architecture, onboarding workflow, and MCP server connection steps, see [`setup/sai/sai_documentation_overview.md`](setup/sai/sai_documentation_overview.md).

## What Gets Deployed

| Resource | Location | Name Pattern |
|---|---|---|
| Safe | Privilege Cloud | `{LAB_ID}-machine-identity` |
| Accounts (3) | Privilege Cloud | `account-db-host`, `account-db-user`, `account-api-key` |
| Conjur Policy | Conjur Cloud | `data/{LAB_ID}-machine-identity` |
| Conjur Host | Conjur Cloud | `data/{LAB_ID}-machine-identity/demo-workload` |
| Secret Store | Secrets Hub | `{LAB_ID}-machine-identity-aws-target` |
| Sync Policy | Secrets Hub | `{LAB_ID}-machine-identity-sync` |
| Connection Target | SIA | `{LAB_ID}-machine-identity-target` |
| cert-manager Issuer | Kubernetes | `cyberark-issuer` in `{LAB_ID}-machine-identity` ns |
| Certificate | Kubernetes | `{LAB_ID}-machine-identity-cert` |
| TLS Secret | Kubernetes | `{LAB_ID}-machine-identity-tls` |
| AI Agent | Secure AI | `SAI_AGENT_NAME` (PENDING_CONNECTION → ACTIVE) |
| MCP Server | AI Gateway | `SIA_DB_MCP_SERVER` |

## Troubleshooting

- **Token errors**: Verify `CLIENT_ID` / `CLIENT_SECRET` in `tenant_vars.sh`
- **Synchronizer timeout**: Safe sync can take 2-5 minutes; the script waits automatically
- **Secrets Hub 403**: Ensure service account has Secrets Hub Admin role
- **SIA 403**: Ensure service account has DpaAdmin role
- **VCert connection error**: Verify `VCERT_API_KEY` (SaaS) or `VCERT_TPP_URL` + credentials (Self-Hosted)
- **cert-manager pending**: Check `kubectl describe certificate` and `kubectl describe certificaterequest` for status
- **cert-manager Issuer not ready**: Check `kubectl describe issuer cyberark-issuer -n $CM_NAMESPACE` for credential or connectivity errors
- **SAI agent 409 Conflict**: Agent name already registered — script handles this (idempotent)
- **SAI agent activation fails**: Agent may need gateway configuration before it can transition to ACTIVE
- **SAI missing Secure AI Builders role**: Reinstall SAI or create role via `POST /roles/storerole`
- **AI Gateway MCP 403**: Ensure service account has Secure AI Admins or Secure AI Builders role
