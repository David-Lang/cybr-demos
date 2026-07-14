# GitHub Actions Demo Setup

This demo provisions the CyberArk Secrets Manager (Idira) server side for GitHub Actions integrations **and** configures the target GitHub repository. It creates a JWT authenticator for GitHub OIDC, a workload identity for a GitHub `actor`, and a Privilege Cloud safe whose secrets are synchronized into Secrets Manager, then maps those values and pushes them to the GitHub repo (variables, secrets, environments). This demo is authoritative; the `idira-github-actions` repo only holds the workflows, Terraform config, and docs.

## Main Entry Point

Run the full setup from the demo directory:

```bash
cd "$CYBR_DEMOS_PATH/demos/secrets_manager/github.com"
./setup.sh
```

`setup.sh` sources `setup/vars.env` and runs three stages in order:

1. `setup/vault/setup.sh` — create the demo safe and a sample account.
2. `setup/conjur/setup.sh` — create and activate the `github1` JWT authenticator and the workload identity.
3. `setup/github/setup.sh` — render `settings_variables.env` with the values GitHub needs.

To reset before another attempt:

```bash
./remove.sh
```

## Deployment Context

This is a control-plane setup, not a host or Kubernetes deployment. The "workload" is a GitHub Actions job that authenticates to Secrets Manager using the repository's GitHub OIDC token.

The repo-specific setup path matters because:

- the safe is provisioned by this repo's shared Privilege Cloud helpers,
- the JWT authenticator and workload policies are created from templates in `setup/conjur/`,
- the workload identity is derived from the GitHub `actor` claim you provide,
- the GitHub-side values are mapped from the rendered `CONJUR_*` and pushed to the repo.

## Required Environment

Prerequisites:

- Linux/macOS with `bash`, `curl`, and `jq`.
- The GitHub CLI (`gh`) installed and authenticated with access to `GH_REPO`.
- `CYBR_DEMOS_PATH` exported and pointing to this repo checkout.
- Tenant variables available through `demos/setup_env.sh` (`demos/tenant_vars.sh` or environment): `LAB_ID`, `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET`.
- The service account (`CLIENT_ID`/`CLIENT_SECRET`) must have policy-admin rights (`Conjur_Cloud_Admins`) to create authenticators and workloads.
- A healthy Conjur Sync so the safe delegation group appears in Secrets Manager.

The setup uses `setup/vars.env` as the shared demo configuration file. It reads these values from the environment (falling back to defaults):

- `SAFE_NAME` — the Privilege Cloud safe to create/use (default `poc-github`).
- `JWT_CLAIM_IDENTITY` — the GitHub `actor` claim value (your GitHub username). Required; the default is a placeholder.
- `GH_REPO` — target GitHub repository `owner/repo` (default `David-Lang/idira-github-actions`).
- `GH_ENVIRONMENTS` — environments to create/seed (default `dev staging main terraform`).
- `TRUFFLEHOG_REPOS` — optional repo list for the trufflehog demo.
- `TFVAR_SSL_CERT`, `TFVAR_sm_secret_id_1` — optional Terraform overrides (derived if blank).

## Setup Flow

### Stage 1: Provision the Demo Safe

`setup/vault/setup.sh`:

- authenticates with the tenant service account,
- creates the safe named by `SAFE_NAME`,
- adds the Privilege Cloud administrators and `Conjur Sync` as members,
- creates the sample account `account-ssh-user-1`,
- waits for the synchronized safe delegation group (`vault/<safe>/delegation/consumers`) to appear in Conjur.

### Stage 2: Provision the JWT Authenticator and Workload

`setup/conjur/setup.sh`:

- applies `authenticator_consumers.yaml` (the `data/authenticator/consumers` group),
- applies `jwt_service_github1.yaml` to create the `conjur/authn-jwt/github1` authenticator,
- sets the authenticator variables:
  - `jwks-uri = https://token.actions.githubusercontent.com/.well-known/jwks`
  - `issuer = https://token.actions.githubusercontent.com`
  - `token-app-property = actor`
  - `identity-path = data/workloads/github-actor`
- activates `authn-jwt/github1`,
- renders and applies `workload1.yaml`, creating the host `data/workloads/github-actor/<JWT_CLAIM_IDENTITY>` (annotated `authn/api-key: true`) and granting it to the authenticator consumers group and to `vault/<safe>/delegation/consumers`.

### Stage 3: Configure the GitHub Repository

`setup/github/setup.sh` renders `settings_variables.env` from `settings_variables.tmpl.env`, producing the `CONJUR_*` values, then maps and pushes them to GitHub (see "GitHub Configuration" below). The rendered values are:

- `CONJUR_ACCOUNT="conjur"`
- `CONJUR_JWT_AUTHN_ID="github1"`
- `CONJUR_SECRET_ID_1="data/vault/<safe>/account-ssh-user-1/username"`
- `CONJUR_SECRET_ID_2="data/vault/<safe>/account-ssh-user-1/password"`
- `CONJUR_URL="https://<subdomain>.secretsmgr.cyberark.cloud/api"`

## GitHub Configuration (Option A: authoritative)

This demo owns the full flow. `setup/github/setup.sh`:

- renders `settings_variables.env` (the `CONJUR_*` values),
- maps them to the `SM_*` names the workflows consume,
- provisions the api-key credential by rotating the workload host's API key (kept in-process, pushed straight to GitHub as a secret),
- derives the Terraform (`TFVAR_*`) values, and
- calls `setup/github/init-gh-vars-secrets.sh` to create the repo variables, secrets, and environments in `GH_REPO`.

Requires the `gh` CLI to be installed and authenticated for `GH_REPO`.

## What Gets Deployed

Local artifacts:

- `setup/github/settings_variables.env` (rendered `CONJUR_*` values; git-ignored)
- `setup/conjur/workload1.yaml` (rendered workload policy)

CyberArk-side resources:

- demo safe named by `SAFE_NAME`, with `account-ssh-user-1`
- JWT authenticator `conjur/authn-jwt/github1` (activated)
- workload host `data/workloads/github-actor/<JWT_CLAIM_IDENTITY>`
- grants into the authenticator consumers group and the safe delegation consumers group

GitHub-side resources (in `GH_REPO`):

- repository variables: `SM_URL`, `SM_ACCOUNT`, `SM_JWT_AUTHN_ID`, `SM_SECRET_ID_1`, `SM_SECRET_ID_2` (and optional `TRUFFLEHOG_REPOS`)
- repository secrets: `SM_USERNAME`, `SM_API_KEY`
- environments: `dev`, `staging`, `main`, and `terraform` (with `TFVAR_*`)

## Troubleshooting Setup

- If the safe setup waits indefinitely for synchronization, confirm `Conjur Sync` was added and the synchronizer is healthy.
- If authenticator or workload creation fails with an authorization error, confirm the service account has `Conjur_Cloud_Admins` rights.
- If `JWT_CLAIM_IDENTITY` is still the placeholder, export a real GitHub `actor` value before running setup.
- If the GitHub stage fails, confirm `gh auth status` succeeds and the token can write variables/secrets/environments to `GH_REPO`.
- If a run fails sourcing the framework, confirm `CYBR_DEMOS_PATH` is exported and `demos/setup_env.sh` resolves the tenant variables.
- To reset the server side before retrying, run `./remove.sh`.
