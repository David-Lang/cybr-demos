# Demo: Summon AWS Auth

Demonstrates how to use Summon on Ubuntu/Linux with CyberArk Secrets Manager and AWS IAM authentication.

Use the repo-standard docs for deployment and validation:

- `demo_setup.md`
- `demo_validation.md`

Key files:

- `setup.sh` installs Summon and the summon-conjur provider
- `setup/vault/setup.sh` provisions the demo safe and sample account
- `setup/conjur/setup.sh` creates the AWS IAM workload policy and writes runtime environment variables
- `demo.sh` validates the AWS caller identity and runs Summon
- `secrets.yml` maps synced safe secrets into environment variables
