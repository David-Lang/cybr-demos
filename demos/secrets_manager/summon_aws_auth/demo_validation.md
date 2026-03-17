# Summon AWS Auth Validation

This validation guide assumes `setup.sh`, `setup/vault/setup.sh`, and `setup/conjur/setup.sh` have already completed and that `conjur_authn_iam.env` has been sourced.

## Quick Validation

Confirm the AWS principal being used by the host:

```bash
aws sts get-caller-identity
```

Confirm the runtime variables are loaded:

```bash
env | grep '^CONJUR_'
```

Run the demo:

```bash
./demo.sh
```

Or run the full non-interactive deployment-and-validation flow:

```bash
bash ./test_runner.sh
```

Success looks like this:

- `aws sts get-caller-identity` returns the expected account and role
- Summon completes without prompting for a Conjur API key
- `consumer.sh` prints the synced address, password, and username values

## Pattern: AWS IAM Authentication

What to validate:

```bash
printf '%s\n' "$CONJUR_AUTHN_URL"
printf '%s\n' "$CONJUR_AUTHN_LOGIN"
aws sts get-caller-identity
```

What this proves:

- the workstation or instance has AWS credentials available
- the demo is targeting the expected `authn-iam` service
- the Conjur host identity matches the AWS role identity derived from STS under the lab-specific `data/$LAB_ID` branch

CyberArk behavior:

- `summon-conjur` uses the AWS IAM authenticator endpoint instead of `authn` with a rotated API key
- CyberArk validates the signed AWS identity and maps it to the configured Conjur host
- once authenticated, the host can read secrets delegated from the synced safe

## Pattern: Safe Sync Consumption Through Summon

Inspect the variable mapping:

```bash
cat secrets.yml
```

That file is rendered during setup from `secrets.tmpl.yml`, so the safe path is concrete before Summon runs.

Run the mapped secret retrieval:

```bash
summon -p summon-conjur bash consumer.sh
```

What this proves:

- the safe synced into Conjur under `data/vault/<safe-name>`
- the workload has delegation rights to the safe consumer group
- Summon can inject secrets into a normal shell process as environment variables

CyberArk behavior:

- Conjur resolves each `!var` path in `secrets.yml`
- the values come from synchronized safe data, not from local files
- the application receives the secrets only for the life of the Summon-managed process

## Troubleshooting

- If `aws sts get-caller-identity` fails, fix the local AWS credential source before checking CyberArk.
- If authentication fails, compare the returned IAM ARN with `AWS_CALLER_ARN` and `WORKLOAD_HOST_ID` in `conjur_authn_iam.env`.
- If Summon authenticates but variable lookup fails, confirm the safe sync completed and that `account-ssh-user-1` exists in the demo safe.
- If you want a clean rerun, execute `bash ./cleanup.sh` before the next deployment attempt.
