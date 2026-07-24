# Summon Azure Auth Setup

This demo deploys a local Summon runtime on an Azure-hosted Ubuntu VM. The workload authenticates to CyberArk Secrets Manager with Azure managed identity and reads secrets synchronized from a Privilege Cloud safe into Conjur.

## Main Entry Point

Run the full setup from the demo directory:

```bash
./setup.sh
```

That script performs deployment enablement (it does **not** create the safe or vault the credential):

1. Installs Summon and the `summon-conjur` provider.
2. Validates that an active PostgreSQL credential platform exists on the tenant.
3. Runs `setup/conjur/setup.sh` to create/configure `authn-azure` and the workload identity.
4. Renders `secrets.yml` from `secrets.tmpl.yml` using the resolved safe name.

The safe and account are created by the **student** in the activity. After the
safe syncs into Conjur, run `setup/conjur/grant_consumers.sh` (control plane) to
grant the workload read access to the safe's consumers group.

For a non-interactive install-plus-validation run on a prepared host:

```bash
bash ./test_runner.sh
```

## Deployment Context

This is a host-based demo, not a Kubernetes deployment. The workload is the local Linux shell process started by Summon on an Azure VM.

The repo-specific setup path matters because:

- the safe is provisioned by this repo's shared Privilege Cloud helpers
- the Conjur policy is created from templates in `setup/conjur/`
- the Azure authenticator service is created if the `apps` group is missing
- the Azure authenticator `provider-uri` is written during setup
- the workload identity is derived from the configured Azure managed identity name
- the runtime environment is written to `conjur_authn_azure.env` for later validation

## Required Environment

Prerequisites:

- Ubuntu VM running in Azure
- user-assigned managed identity attached to the VM
- `bash`, `curl`, `tar`, `sudo`, and `jq`
- `az` is recommended for interactive validation
- `CYBR_DEMOS_PATH` exported and pointing to this repo checkout
- tenant variables available through `demos/setup_env.sh`

The setup uses `setup/vars.env` as the shared demo configuration file. Set these values before running setup:

- `AUTHN_AZURE_SERVICE_ID`

`SAFE_NAME` defaults to the **VM name** (the host's short hostname, which Azure
sets to `{labid}-{noun}-{verb}-{4char}` and is kept within the 28-char safe cap).
Override it by exporting `SAFE_NAME` (or `VM_NAME`) before setup — needed only if
setup does not run on the target VM, or a long custom instance name would exceed
28 characters.

These values can usually be discovered from Azure IMDS and may be left blank:

- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_USER_ASSIGNED_IDENTITY_NAME`

Set `AZURE_CLIENT_ID` when the VM has multiple managed identities attached. If setup cannot discover the user-assigned identity name from the Azure token, set `AZURE_USER_ASSIGNED_IDENTITY_NAME` explicitly.

Constraints and assumptions:

- `SAFE_NAME` must not exceed 28 characters.
- `AZURE_USER_ASSIGNED_IDENTITY_NAME` is case-sensitive.
- CyberArk's Azure authenticator examples use the managed identity name, not the client ID, in the `authn-azure/user-assigned-identity` annotation.
- `AZURE_CLIENT_ID` is optional for policy, but required for IMDS token selection when more than one managed identity is attached.
- The generated workload host lives under `host/data/<LAB_ID>/azure-apps/<host-name>`.

## Setup Flow

`setup.sh` orchestrates four concrete stages.

### Stage 1: Install Summon Runtime

`../../../compute_init/ubuntu/install_summon.sh` installs:

- `summon`
- the `summon-conjur` provider

This host runtime later authenticates to CyberArk and injects variables into the child process.

### Stage 2: Validate the Postgres Credential Platform

Deployment validates that an **active PostgreSQL credential platform** exists on
the tenant (via `postgres_platform_available`). The student needs it to onboard
the DB account and SRS needs it to rotate the credential, so setup fails early if
it is missing. Override the match keyword with `POSTGRES_PLATFORM_ID`.

> **Required platform config (rotation):** the PostgreSQL platform's **connection
> command** must reference the ODBC driver name that is actually installed on the
> connector (`PostgreSQL Unicode`). A mismatch here causes rotation to fail with
> `IM002 ... Data source name not found and no default driver specified` even
> though the driver is installed. When the `PostgreSQL` platform is set up, set
> its connection command (Platform settings → the PostgreSQL connection
> component) to:
>
> ```
> Driver={PostgreSQL Unicode};Server=%ADDRESS%;[Database=%DATABASE%;]Uid=%USER%;Pwd=%LOGONPASSWORD%;[Port=%PORT%]
> ```
>
> The connector host has both the 64-bit and 32-bit psqlODBC drivers installed
> automatically by `setup/idira/system-connector.sh`; `PostgreSQL Unicode`
> resolves in both bitnesses.

The safe and the `postgres-appuser` account are **not** created here — the student creates
the safe and vaults the credential in the activity. After the safe syncs into
Conjur, run `setup/conjur/grant_consumers.sh` (control plane) to grant the
workload read access to the safe's consumers group.

### Stage 3: Provision Azure Authenticator and Workload

`setup/conjur/setup.sh`:

- authenticates to CyberArk using the repo tenant variables
- validates that the VM can retrieve an Azure managed identity token from IMDS
- creates `conjur/authn-azure/<service-id>` if needed
- sets `conjur/authn-azure/<service-id>/provider-uri`
- enables `authn-azure/<service-id>`
- creates the workload policy under `data/<LAB_ID>/azure-apps`
- grants the workload group to `authn-azure/<service-id>/apps`
- grants the workload group to `vault/<safe-name>/delegation/consumers`
- writes `conjur_authn_azure.env`

This stage creates both control points needed at runtime:

- authentication permission through `authn-azure`
- authorization permission to read synced safe variables

### Stage 4: Render the Runtime Secret Map

`setup.sh` renders `secrets.yml` from `secrets.tmpl.yml` for the post-vault smoke
test (`demo.sh`). It points to the account the student vaults:

- `data/vault/<safe-name>/postgres-appuser/username`
- `data/vault/<safe-name>/postgres-appuser/password`

It resolves only after the student vaults that account and the workload is
granted access (`grant_consumers.sh`). The workshop itself uses the activity's
own `secrets.yml`, rendered per student by `activity/setup_activity.sh`.

## What Gets Deployed

Local host artifacts:

- `conjur_authn_azure.env`
- `secrets.yml` (post-vault smoke-test map)
- Summon binaries and provider
- the VM-local Postgres container + seeded demo table (`activity/db_setup.sh`)
- the rendered student workspace under `/opt/labs`

CyberArk-side resources:

- Conjur authenticator service under `conjur/authn-azure/<service-id>`
- `provider-uri` variable value for the Azure tenant
- Conjur workload host under `data/<LAB_ID>/azure-apps/<host-name>`
- Conjur grant into the `authn-azure` `apps` group

NOT created at deploy (the student does this in the activity):

- the safe (named after the VM) and the vaulted `postgres-appuser` account
- the safe-consumers grant — applied afterward by `setup/conjur/grant_consumers.sh`

## Cleanup Scope

`cleanup.sh` removes:

- the demo workload policy branch
- the demo account and safe
- generated local runtime files
- captured test artifacts

`cleanup.sh` intentionally leaves this in place:

- `conjur/authn-azure/<service-id>`
- `provider-uri`
- authenticator activation state

That avoids breaking other demos or workloads that may reuse the Azure authenticator service.

## Troubleshooting Setup

- If IMDS token retrieval fails, confirm the VM is running in Azure and has the user-assigned identity attached.
- If the VM has multiple managed identities, set `AZURE_CLIENT_ID` in `setup/vars.env`.
- If setup reports a missing `authn-azure` service, re-run `setup/conjur/setup.sh`; it creates the service policy when the `apps` group is absent.
- If the safe setup waits indefinitely for synchronization, confirm `Conjur Sync` was added successfully and the synchronizer is healthy.
- If setup completes but `secrets.yml` is missing, re-run `./setup.sh` and confirm `SAFE_NAME` is present in `setup/vars.env`.
- If you need to reset the demo before another attempt, run `bash ./cleanup.sh`.
