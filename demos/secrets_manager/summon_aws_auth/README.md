# Demo: Summon AWS Auth

Demonstrates how to use Summon on Ubuntu/Linux with CyberArk Secrets Manager and AWS IAM authentication.

Use the repo-standard docs for deployment and validation:

- `demo_setup.md`
- `demo_validation.md`

Key files:

- `setup.sh` installs Summon, provisions the safe, provisions the Conjur workload, and writes the runtime environment file
- `setup/vault/setup.sh` provisions the demo safe and sample account
- `setup/conjur/setup.sh` creates the AWS IAM workload policy and writes runtime environment variables
- `setup/vars.env` is the single configuration file for safe name, authn-iam service, and region
- `test_runner.sh` performs install, deployment, validation, and artifact capture
- `cleanup.sh` removes the workload host, demo safe, and local artifacts for reruns
- `demo.sh` validates the AWS caller identity and runs Summon
- `secrets.tmpl.yml` is the template for Summon variable mappings
- `secrets.yml` is rendered during setup with the resolved safe name
