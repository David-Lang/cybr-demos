# Standalone Summon And Azure Workload Setup

This guide starts from scratch. It is intentionally independent of the `cybr-demos` helper scripts.

Use it when you need to prepare an Ubuntu VM so a script can retrieve CyberArk Secrets Manager values with Summon, `summon-conjur`, and Azure managed identity authentication.

References:

- Summon: https://github.com/cyberark/summon
- Summon Conjur provider: https://github.com/cyberark/summon-conjur
- CyberArk Azure managed identity example: https://developer.cyberark.com/blog/using-cyberark-conjur-with-azure-serverless-functions-and-managed-identities/
- CyberArk Azure workload auth overview: https://docs.cyberark.com/secrets-manager-saas/latest/en/content/operations/authn/authenticate-azure-overview.htm

## 1. Install Linux Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl jq tar
```

If this activity queries a local PostgreSQL with `psql`, install the client:

```bash
sudo apt-get install -y postgresql-client
```

## 2. Install Summon

Choose a Summon version from the GitHub releases page:

```bash
SUMMON_VERSION="v0.11.0"
tmp_dir="$(mktemp -d)"
cd "$tmp_dir"

curl -fSL \
  "https://github.com/cyberark/summon/releases/download/${SUMMON_VERSION}/summon-linux-amd64.tar.gz" \
  -o summon-linux-amd64.tar.gz

tar -xzf summon-linux-amd64.tar.gz
sudo install -m 0755 summon /usr/local/bin/summon

summon -h
```

Summon reads a `secrets.yml` file, asks a provider to resolve secret values, and injects those values into the environment of the child process it starts.

## 3. Install summon-conjur

Choose a provider version from the `summon-conjur` GitHub releases page:

```bash
SUMMON_CONJUR_VERSION="v0.9.3"
tmp_dir="$(mktemp -d)"
cd "$tmp_dir"

curl -fSL \
  "https://github.com/cyberark/summon-conjur/releases/download/${SUMMON_CONJUR_VERSION}/summon-conjur-linux-amd64.tar.gz" \
  -o summon-conjur-linux-amd64.tar.gz

tar -xzf summon-conjur-linux-amd64.tar.gz
sudo mkdir -p /usr/local/lib/summon
sudo install -m 0755 summon-conjur /usr/local/lib/summon/summon-conjur

test -x /usr/local/lib/summon/summon-conjur
```

Summon looks for providers in `/usr/local/lib/summon` on Linux. You can also pass the provider explicitly:

```bash
summon --provider summon-conjur -f ./secrets.yml env
```

## 4. Prepare Azure Managed Identity

The Ubuntu VM must run in Azure and have a managed identity attached.

For this activity, a user-assigned managed identity is easiest to reason about. Record these values:

```bash
AZURE_TENANT_ID="<entra-tenant-guid>"
AZURE_SUBSCRIPTION_ID="<azure-subscription-guid>"
AZURE_RESOURCE_GROUP="<resource-group-containing-the-identity>"
AZURE_USER_ASSIGNED_IDENTITY_NAME="<user-assigned-identity-name>"
AZURE_CLIENT_ID="<identity-client-id>"
```

Notes:

- `AZURE_CLIENT_ID` is required when the VM has more than one managed identity attached.
- CyberArk Azure authenticator examples use the user-assigned identity name, not the client ID, in the workload annotation.
- The user-assigned identity name is case-sensitive.

Validate the VM can obtain a token from Azure Instance Metadata Service:

```bash
resource="$(jq -rn --arg value "https://management.azure.com/" '$value|@uri')"
url="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${resource}"

if [ -n "${AZURE_CLIENT_ID:-}" ]; then
  client_id="$(jq -rn --arg value "$AZURE_CLIENT_ID" '$value|@uri')"
  url="${url}&client_id=${client_id}"
fi

curl -fsS -H Metadata:true "$url" | jq '{client_id, resource, token_type, expires_on}'
```

## 5. Create The Azure Authenticator Service

In CyberArk Secrets Manager, create an `authn-azure` service if one does not already exist.

Example policy to load on branch `conjur/authn-azure`:

```yaml
# metadata
# mode: append-policy
---
- !policy
  id: azure-1
  body:
  - !webservice

  - !variable
    id: provider-uri

  - !group
    id: apps
    annotations:
      description: Group of hosts that can authenticate using authn-azure/azure-1

  - !permit
    role: !group apps
    privilege: [ read, authenticate, update ]
    resource: !webservice
```

Set the service `provider-uri` variable:

```text
conjur/authn-azure/azure-1/provider-uri = https://sts.windows.net/<AZURE_TENANT_ID>/
```

Enable the service:

```text
authn-azure/azure-1
```

How you load policy, set variable values, and enable authenticators depends on your tenant tooling. Use your Secrets Manager policy loader, Conjur CLI/API process, or the `setup/conjur/setup.sh` automation in the parent `summon_azure_auth` demo.

## 6. Create The Azure Workload Host

Create a workload host that matches the Azure managed identity.

Example policy to load on branch `data`:

```yaml
# metadata
# mode: append-policy
---
- !policy
  id: lab01
  body:
  - !policy
    id: azure-apps
    body:
    - !group

    - &hosts
      - !host
        id: lab01-uami
        annotations:
          description: Azure VM workload for Summon
          authn-azure/subscription-id: <AZURE_SUBSCRIPTION_ID>
          authn-azure/resource-group: <AZURE_RESOURCE_GROUP>
          authn-azure/user-assigned-identity: <AZURE_USER_ASSIGNED_IDENTITY_NAME>

    - !grant
      role: !group
      members: *hosts
```

Grant the workload group to the Azure authenticator `apps` group.

Example policy to load on branch `conjur/authn-azure`:

```yaml
# metadata
# mode: append-policy
---
- !grant
  roles:
    - !group azure-1/apps
  members:
    - !group /data/lab01/azure-apps
```

Grant the same workload group to the safe delegation group for each safe it should read.

Example policy to load on branch `data`:

```yaml
# metadata
# mode: append-policy
---
- !grant
  roles:
    - !group vault/<SAFE_NAME>/delegation/consumers
  members:
    - !group /data/lab01/azure-apps
```

## 7. Configure Runtime Environment

Create an environment file, for example `conjur_authn_azure.env`:

```bash
export CONJUR_APPLIANCE_URL="https://<tenant-subdomain>.secretsmgr.cyberark.cloud"
export CONJUR_ACCOUNT="conjur"
export CONJUR_AUTHN_TYPE="azure"
export CONJUR_SERVICE_ID="azure-1"
export CONJUR_AUTHN_JWT_HOST_ID="data/lab01/azure-apps/lab01-uami"
export CONJUR_AUTHN_LOGIN="host/${CONJUR_AUTHN_JWT_HOST_ID}"
```

Load it before running Summon:

```bash
source ./conjur_authn_azure.env
```

If `summon-conjur` cannot retrieve the Azure token from metadata in your environment, fetch the token yourself and pass it explicitly:

```bash
resource="$(jq -rn --arg value "https://management.azure.com/" '$value|@uri')"
url="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${resource}"

if [ -n "${AZURE_CLIENT_ID:-}" ]; then
  client_id="$(jq -rn --arg value "$AZURE_CLIENT_ID" '$value|@uri')"
  url="${url}&client_id=${client_id}"
fi

export CONJUR_AUTHN_JWT_TOKEN="$(curl -fsS -H Metadata:true "$url" | jq -r '.access_token')"
```

## 8. Create secrets.yml

Map process environment variables to CyberArk variable paths. `psql` reads
`PGUSER`/`PGPASSWORD` natively, so map those directly to the vaulted account:

```yaml
PGUSER: !var data/vault/<SAFE_NAME>/postgres-appuser/username
PGPASSWORD: !var data/vault/<SAFE_NAME>/postgres-appuser/password
```

Keep non-secret connection values as normal configuration (set in the script):

```bash
export PGHOST=localhost
export PGDATABASE=trainingdb
```

## 9. Run The Secured Script

The secured script should read connection values from environment variables:

```bash
summon --provider summon-conjur -f ./secrets.yml ./query_db_secured.sh
```

For this activity, the wrapper does that for students:

```bash
./run_secured_query.sh
```

## Troubleshooting

- `summon: command not found`: install Summon or confirm `/usr/local/bin` is on `PATH`.
- `provider summon-conjur not found`: confirm `/usr/local/lib/summon/summon-conjur` exists and is executable.
- Azure token retrieval fails: confirm the VM is running in Azure and the managed identity is attached.
- Multiple identities are attached: set `AZURE_CLIENT_ID` so IMDS returns the intended identity token.
- Authentication fails: check `provider-uri`, `CONJUR_SERVICE_ID`, `CONJUR_AUTHN_JWT_HOST_ID`, and the Azure host annotations.
- Secret lookup fails after authentication: confirm the workload group is granted to `vault/<SAFE_NAME>/delegation/consumers`.
