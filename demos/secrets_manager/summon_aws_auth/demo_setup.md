# Summon AWS Auth Setup

This demo deploys a local Summon runtime that authenticates to CyberArk Secrets Manager with AWS IAM and reads secrets that were synchronized from a Privilege Cloud safe into Conjur.

## Main Entry Point

Run the full setup from the demo directory:

```bash
./setup.sh
```

That script performs the complete repo deployment flow:

1. Installs Summon and the `summon-conjur` provider.
2. Runs `setup/vault/setup.sh` to create the demo safe and sample account.
3. Runs `setup/conjur/setup.sh` to create the AWS IAM workload identity and grants.
4. Renders `secrets.yml` from `secrets.tmpl.yml` using the resolved safe name.

For a non-interactive install-plus-validation run on a prepared host:

```bash
bash ./test_runner.sh
```

## Deployment Context

This is a host-based demo, not a Kubernetes deployment. The workload is the local Linux shell process started by Summon.

The repo-specific setup path matters because:

- the safe is provisioned by this repo's shared Privilege Cloud helpers
- the Conjur policy is created from templates in `setup/conjur/`
- the workload identity is derived from the live AWS caller returned by `aws sts get-caller-identity`
- the runtime environment is written to `conjur_authn_iam.env` for later validation

## Required Environment

Prerequisites:

- Ubuntu or Linux with `bash`, `curl`, `tar`, `sudo`, `jq`, and `aws`
- `CYBR_DEMOS_PATH` exported and pointing to this repo checkout
- tenant variables available through `demos/setup_env.sh`
- a working AWS IAM principal that can call `sts:GetCallerIdentity`
- an existing CyberArk `authn-iam` service in the target tenant

The setup uses `setup/vars.env` as the shared demo configuration file. Set these values before running setup:

- `SAFE_NAME`
- `AUTHN_IAM_SERVICE_ID`
- `AWS_REGION`

Constraints and assumptions:

- `SAFE_NAME` must not exceed 28 characters
- the active AWS identity must resolve to either an assumed-role ARN or role ARN
- the generated workload host lives under `host/data/<LAB_ID>/<aws-account-id>/<aws-role-path>`

For example, if AWS returns:

```text
arn:aws:sts::123456789012:assumed-role/example-summon-role/session-name
```

the Conjur host becomes:

```text
host/data/<LAB_ID>/123456789012/example-summon-role
```

## Setup Flow

`setup.sh` orchestrates three concrete stages.

### Stage 1: Install Summon Runtime

`../../../compute_init/ubuntu/install_summon.sh` installs:

- `summon`
- the `summon-conjur` provider

This host runtime is what later authenticates to CyberArk and injects variables into the child process.

### Stage 2: Provision the Demo Safe

`setup/vault/setup.sh`:

- creates the demo safe
- adds the required safe members
- adds `Conjur Sync`
- creates `account-ssh-user-1`
- waits for the synchronized safe delegation group to appear in Conjur

This stage establishes the secret source that Summon will eventually consume.

### Stage 3: Provision the AWS IAM Workload

`setup/conjur/setup.sh`:

- authenticates to CyberArk using the repo tenant variables
- resolves the live AWS caller identity with `aws sts get-caller-identity`
- derives the workload host ID from the AWS account and role path
- creates the workload policy under `data/$LAB_ID`
- grants that host to the `authn-iam/<service-id>/consumers` group
- grants that host to `vault/<safe-name>/delegation/consumers`
- writes `conjur_authn_iam.env`

This stage creates both control points needed at runtime:

- authentication permission through `authn-iam`
- authorization permission to read synced safe variables

### Stage 4: Render the Runtime Secret Map

After the safe exists, `setup.sh` renders `secrets.yml` from `secrets.tmpl.yml`.

The rendered file points to:

- `data/vault/<safe-name>/account-ssh-user-1/address`
- `data/vault/<safe-name>/account-ssh-user-1/password`
- `data/vault/<safe-name>/account-ssh-user-1/username`

## What Gets Deployed

Local host artifacts:

- `conjur_authn_iam.env`
- `secrets.yml`
- Summon binaries and provider

CyberArk-side resources:

- demo safe named by `SAFE_NAME`
- sample account `account-ssh-user-1`
- Conjur host under `data/$LAB_ID/<aws-account-id>/<aws-role-path>`
- Conjur grant into the `authn-iam` consumers group
- Conjur grant into the safe delegation consumers group

## Troubleshooting Setup

- If `aws sts get-caller-identity` fails, fix the local AWS credential source before retrying setup.
- If `setup/conjur/setup.sh` reports an unsupported ARN, use an IAM role or assumed-role session instead of a user identity.
- If the safe setup waits indefinitely for synchronization, confirm `Conjur Sync` was added successfully and the synchronizer is healthy.
- If the `authn-iam` patch fails, verify `AUTHN_IAM_SERVICE_ID` matches an existing service in the tenant.
- If setup completes but `secrets.yml` is missing, re-run `./setup.sh` and confirm `SAFE_NAME` is present in `setup/vars.env`.
- If you need to reset the demo before another attempt, run `bash ./cleanup.sh`.
