# Summon AWS Auth Setup

This demo shows Summon on Ubuntu or Linux authenticating to CyberArk Secrets Manager with AWS IAM instead of a rotated Conjur API key.

The repo setup path has three stages:

1. `./setup.sh` installs Summon and the `summon-conjur` provider.
2. `./setup/vault/setup.sh` creates the demo safe, adds `Conjur Sync`, and creates the sample account used by `secrets.yml`.
3. `./setup/conjur/setup.sh` creates the Conjur workload policy for the AWS IAM role and writes `conjur_authn_iam.env` for the runtime session.

## Prerequisites

- Ubuntu or Linux with `bash`, `curl`, `tar`, `sudo`, `jq`, and `aws`
- `CYBR_DEMOS_PATH` is already exported and points to this repo checkout
- Tenant variables configured for this repo in `demos/tenant_vars.sh`
- CyberArk tenant environment variables are already populated and ready to use through `demos/setup_env.sh`
- An AWS IAM principal that can call `sts:GetCallerIdentity`
- A CyberArk `authn-iam` service that already exists in the tenant

The setup scripts assume the shared repo environment is already available. In practice that means:

- `CYBR_DEMOS_PATH` resolves to the root of this repository
- `demos/setup_env.sh` can load the tenant configuration successfully
- the CyberArk variables used by the shared setup functions are already present and valid for the target tenant

## Required Variables

Set these in `setup/vars.env` before running the setup scripts:

- `SAFE_NAME`
- `AUTHN_IAM_SERVICE_ID`
- `AWS_REGION`

`setup/conjur/setup.sh` derives the AWS account and role path from:

```bash
aws sts get-caller-identity
```

The generated workload identity is:

```text
host/data/workloads/aws-iam/<account-from-sts>/<role-path-from-sts>
```

For an assumed role ARN such as:

```text
arn:aws:sts::123456789012:assumed-role/example-summon-role/session-name
```

the generated Conjur host becomes:

```text
host/data/workloads/aws-iam/123456789012/example-summon-role
```

## Deployment Flow

Run the install step:

```bash
./setup.sh
```

Provision the safe and demo account:

```bash
bash ./setup/vault/setup.sh
```

Provision the workload policy and runtime env file:

```bash
bash ./setup/conjur/setup.sh
source ./conjur_authn_iam.env
```

## What Gets Configured

`setup/vault/setup.sh`:

- creates the demo safe
- grants `Privilege Cloud Administrators`
- adds `Conjur Sync`
- creates `account-ssh-user-1`
- waits for the safe delegation group to appear in Conjur

`setup/conjur/setup.sh`:

- authenticates to CyberArk using the repo tenant variables
- resolves the active AWS caller identity with `aws sts get-caller-identity`
- creates a host under `data/workloads/aws-iam`
- grants the host access to the configured `authn-iam` consumer group
- grants the host access to the safe delegation group
- writes `conjur_authn_iam.env`

## Troubleshooting Setup

- If `setup/vault/setup.sh` stalls waiting for synchronization, confirm the safe exists and `Conjur Sync` was added successfully.
- If `setup/conjur/setup.sh` fails patching the IAM consumer group, verify the `authn-iam` service already exists and the `AUTHN_IAM_SERVICE_ID` value is correct.
- If `setup/conjur/setup.sh` fails before policy creation, run `aws sts get-caller-identity` manually and confirm it returns an assumed-role or role ARN.
- If Summon later fails to authenticate, compare the AWS caller ARN with `AWS_CALLER_ARN` and `WORKLOAD_HOST_ID` in `conjur_authn_iam.env`.
