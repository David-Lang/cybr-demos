# Demo: Summon Ubuntu

## About

Demonstrates how to use Summon on Ubuntu/Linux with CyberArk Secrets Manager workload identity.

## Prerequisites

- Ubuntu/Linux with `bash`, `curl`, `tar`, and `sudo`
- Access to CyberArk tenant variables configured for this repo
- Codex session with CyberArk demo MCP tools enabled

## Setup

Run local setup to install Summon and the Conjur provider:

```bash
./setup.sh
```

## Provision with Setup Scripts

If you want script-based provisioning in the demo directory:

```bash
bash ./setup/vault/setup.sh
bash ./setup/conjur/setup.sh
source ./conjur_credentials.env
```

## Provision with MCP Tools

Provision demo infrastructure using MCP tools:

1. Provision a safe and demo account:
   - `mcp__cybr-demos__provision_safe`
   - `demoPath: secrets_manager/summon_ubuntu`
   - `safeName: <your-safe-name>`
   - `addSyncMember: true`
   - `createAccounts: true`
   - `setupConjur: true`

2. Provision workload identity:
   - `mcp__cybr-demos__provision_workload`
   - `demoPath: secrets_manager/summon_ubuntu`
   - `safeName: <your-safe-name>`
   - `workloadName: summon-ubuntu`

After workload provisioning, source the generated credentials file:

```bash
source ./conjur_credentials.env
```

## Running the Demo

```bash
./demo.sh
```

## Workflow

1. `demo.sh` verifies Conjur auth variables.
2. Summon reads `secrets.yml` and fetches mapped secrets.
3. `consumer.sh` receives secrets as environment variables.

## Files

- `setup.sh` - Local installer and MCP provisioning guidance
- `setup/setup.sh` - Installs Summon and summon-conjur
- `setup/vault/setup.sh` - Safe setup scaffold generated via MCP demo tooling
- `setup/conjur/setup.sh` - Creates workload host, grants safe delegation access, writes credentials
- `secrets.yml` - Summon variable mappings
- `demo.sh` - Runs Summon with `consumer.sh`
- `consumer.sh` - Prints injected secret variables

## Documentation

- Summon: https://cyberark.github.io/summon/
- Summon Conjur Provider: https://github.com/cyberark/summon-conjur
