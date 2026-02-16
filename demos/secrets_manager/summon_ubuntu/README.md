# Demo: Summon Ubuntu

## About

Demonstrates how to use Summon on Ubuntu/Linux with CyberArk Secrets Manager workload identity.

## Prerequisites

- Ubuntu/Linux with `bash`, `curl`, `tar`, and `sudo`
- Access to CyberArk tenant variables configured for this repo

## Setup

Install Summon and the summon-conjur provider:

```bash
./setup.sh
```

Then provision the demo resources:

```bash
bash ./setup/vault/setup.sh
bash ./setup/conjur/setup.sh
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

- `setup.sh` - Installs Summon and prints local provisioning steps
- `setup/vault/setup.sh` - Creates demo safe, members, and account
- `setup/conjur/setup.sh` - Creates workload host, grants safe delegation access, writes `conjur_credentials.env`
- `setup/conjur/workload.tmpl.yaml` - Template for workload host policy
- `setup/conjur/grant_safe_access.tmpl.yaml` - Template for safe delegation grant
- `secrets.yml` - Summon variable mappings
- `demo.sh` - Runs Summon with `consumer.sh`
- `consumer.sh` - Prints injected secret variables

## Documentation

- Summon: https://cyberark.github.io/summon/
- Summon Conjur Provider: https://github.com/cyberark/summon-conjur
