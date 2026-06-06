# MCP Server Tools Reference

Five tools are available. The CLI under `tools/cli/` is the source of truth for behavior. If this document conflicts with the CLI, update this file.

---

## create_demo

Scaffolds a new demo directory with README.md, info.yaml, demo.sh, setup.sh, and setup/configure.sh. All scripts are made executable with proper shebangs, error handling, and env var sourcing.

**CLI:** `node tools/cli/cybr-demos.js create-demo`

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `category` | string (enum) | Yes | `credential_providers`, `secrets_manager`, `secrets_hub`, or `utility` |
| `name` | string | Yes | Demo name (converted to lowercase with underscores for directory) |
| `displayName` | string | No | Display name for README/info.yaml. Defaults to `name`. |
| `categoryLabel` | string | No | Custom category label for info.yaml. Defaults to `category`. |
| `description` | string | No | Description for README About section. |
| `docs` | string | No | Documentation URL. Defaults to CyberArk docs portal. |
| `demoScript` | string | No | Demo script filename. Defaults to `demo.sh`. |
| `setupScript` | string | No | Setup script filename. Defaults to `setup.sh`. |

### Output

```
demos/{category}/{demo_name}/
├── README.md
├── info.yaml
├── demo.sh
├── setup.sh
└── setup/
    └── configure.sh
```

---

## create_demo_safe

Generates a `setup/vault/` directory with scripts to create and configure a CyberArk Privilege Cloud safe. Requires an existing demo directory.

**CLI:** `node tools/cli/cybr-demos.js create-demo-safe`

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `demoPath` | string | Yes | Path relative to `demos/` (e.g., `secrets_manager/azure_devops`) |
| `safeName` | string | No | Safe name. Defaults to `${LAB_ID}-{demo-name}` (normalized). |
| `addSyncMember` | boolean | No | Add "Conjur Sync" read member. Defaults to `true` for `secrets_manager` demos. |
| `createAccount` | boolean | No | Include test SSH account creation. Defaults to `false`. |
| `setupConjur` | boolean | No | Include Conjur synchronizer setup. Defaults to `false`. |
| `additionalVars` | string | No | Extra env vars for `vars.env` (multiline shell definitions). |

### Output

```
demos/{category}/{demo_name}/
└── setup/
    ├── vars.env
    └── vault/
        └── setup.sh
```

### Generated Files

#### setup/vars.env
Contains demo-level environment variables shared across setup stages:
```bash
# CyberArk Vault
SAFE_NAME="${LAB_ID}-azure-devops"

# Add additional environment variables here
```
Note: If you provide a custom `safeName`, that value will be used instead of the default pattern.
Preferred structure:
- Keep `SAFE_NAME` and related demo settings in `setup/vars.env`
- Avoid creating a second `setup/vault/vars.env` unless there is a documented exception

#### setup/vault/setup.sh
Vault setup script that:
1. Sources common environment and utility functions
2. Loads variables from `setup/vars.env`
3. Gets Identity authentication token
4. Creates the safe
5. Adds admin role permissions
6. Optionally adds Conjur Sync member
7. Optionally creates test accounts
8. Optionally sets up Conjur synchronization

### Response

Returns a JSON object:

```json
{
  "success": true,
  "path": "/full/path/to/demos/category/demo_name/setup",
  "files": [
    "vars.env",
    "vault/setup.sh"
  ]
}
```

### Dependencies

The generated scripts depend on functions from:

- **`demos/setup_env.sh`** - Loads all utility functions
- **`demos/tenant_vars.sh`** - Tenant configuration
- **`demos/utility/ubuntu/identity_functions.sh`** - Identity token functions
- **`demos/utility/ubuntu/privilege_functions.sh`** - Safe/account functions
- **`demos/utility/ubuntu/priviledge_functions.sh`** - Back-compat shim (sources `privilege_functions.sh`; prefer the correctly spelled path)
- **`demos/utility/ubuntu/conjur_functions.sh`** - Conjur sync functions

### Required Environment Variables

Set these in `demos/tenant_vars.sh`:

```bash
TENANT_ID="your-tenant-id"
TENANT_SUBDOMAIN="your-subdomain"
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-client-secret"
LAB_ID="your-lab-id"  # Used for default safe names (e.g., "poc", "lab01", "demo")
```

Note: `LAB_ID` is used in the default safe name pattern `${LAB_ID}-{demo-name}`. This allows you to create unique safe names across different lab environments without manually specifying the safe name each time.

### Usage Workflow

1. **Create demo** (if not exists):
   ```
   Create a secrets_manager demo called "azure_devops"
   ```

2. **Create safe setup**:
   ```
   Create a demo safe for secrets_manager/azure_devops with safe name "poc-azure-devops"
   ```

3. **Run the setup**:
   ```bash
   cd demos/secrets_manager/azure_devops/setup/vault
   ./setup.sh
   ```

### API Functions Used

The generated scripts use these CyberArk API functions:

- **`get_identity_token()`** - Authenticate to Identity
- **`create_safe()`** - Create safe via Privilege Cloud API
- **`add_safe_admin_role()`** - Add admin permissions
- **`add_safe_read_member()`** - Add read-only member (for Conjur Sync)
- **`create_account_ssh_user_1()`** - Create test SSH account
- **`get_conjur_token()`** - Get Conjur authentication token
- **`wait_for_synchronizer()`** - Wait for Conjur to detect the safe

### Common Use Cases

#### 1. Simple Safe for API Testing (Default Name)
```
demoPath: "secrets_manager/api_test"
```
Safe name will be: `${LAB_ID}-api-test`

#### 2. Secrets Manager with Conjur Sync (Default Name)
```
demoPath: "secrets_manager/k8s"
addSyncMember: true
setupConjur: true
createAccount: true
```
Safe name will be: `${LAB_ID}-k8s`

#### 3. Credential Provider Demo (Custom Name)
```
demoPath: "credential_providers/ccp"
safeName: "poc-ccp-accounts"
createAccount: true
```

#### 4. GitHub Actions with JWT (Custom Name)
```
demoPath: "secrets_manager/github_actions"
safeName: "poc-github"
additionalVars: 'JWT_CLAIM_IDENTITY="INPUT_REQUIRED: github-name"'
```

### Troubleshooting

#### Demo Path Not Found
Ensure the demo directory exists before creating safe setup:
```bash
ls -la demos/secrets_manager/azure_devops
```

#### Missing Environment Variables
Source the tenant variables:
```bash
source demos/tenant_vars.sh
echo $TENANT_ID
```

#### Permission Errors
Ensure scripts are executable:
```bash
chmod +x setup/vault/*.sh
```

### Best Practices

1. **Use default safe names**: Let the tool generate `${LAB_ID}-{demo-name}` automatically unless you need a specific name
2. **Set LAB_ID appropriately**: Use values like "poc", "lab01", "demo" to identify your lab environment
3. **Enable Conjur Sync** when using Secrets Manager/Secrets Hub
4. **Create test accounts** for demos that need them
5. **Document custom variables** in the demo's README
6. **Test safe creation** before running full demo setup

---

## provision_safe

Executes live API calls to create a safe in CyberArk Privilege Cloud. Unlike `create_demo_safe` (which generates scripts), this tool provisions immediately using env vars from `tenant_vars.sh`.

**CLI:** `node tools/cli/cybr-demos.js provision-safe`

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `demoPath` | string | Yes | Path relative to `demos/` |
| `safeName` | string | Yes | Safe name (e.g., `poc-azure-devops`) |
| `addSyncMember` | boolean | No | Add "Conjur Sync" member. Defaults to `false`. |
| `createAccounts` | boolean | No | Create test SSH account (`account-ssh-user-1`). Defaults to `false`. |
| `setupConjur` | boolean | No | Wait for Conjur synchronizer. Requires `addSyncMember`. Defaults to `false`. |

### Execution flow

1. Authenticate to CyberArk Identity (OAuth)
2. Create safe via Privilege Cloud API
3. Add admin role permissions
4. Optionally: add Conjur Sync member, create test accounts, wait for sync

### Requires

- `CYBR_DEMOS_PATH` set
- `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET` in `demos/tenant_vars.sh`
- Network access to CyberArk Privilege Cloud

---

## provision_workload

Creates a Secrets Manager workload with API key authentication and grants it access to an existing safe. Complements `provision_safe` -- create the safe first, then create workloads.

**CLI:** `node tools/cli/cybr-demos.js provision-workload`

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `demoPath` | string | Yes | Path relative to `demos/` |
| `safeName` | string | Yes | Existing safe to grant access to |
| `workloadName` | string | Yes | Workload identifier (created as `data/workloads/{workloadName}`) |

### Execution flow

1. Authenticate to Identity and Conjur
2. Create workload policy (host with `authn/api-key: true`)
3. Grant workload consumer access to the safe
4. Rotate API key
5. Save credentials to `setup/.workload_credentials_{workloadName}.txt` (mode 600)

### Conjur policy created

```yaml
- !host
  id: workloads/{workloadName}
  annotations:
    authn/api-key: true
- !grant
  roles:
    - !group vault/{safeName}/delegation/consumers
  members:
    - !host workloads/{workloadName}
```

### Using the credentials

```bash
# Authenticate
TOKEN=$(curl -s -d "$API_KEY" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn/conjur/host%2Fdata%2Fworkloads%2F$WORKLOAD/authenticate" \
  | base64 | tr -d '\r\n')

# Retrieve secret
curl -H "Authorization: Token token=\"$TOKEN\"" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2F$SAFE%2F$ACCOUNT%2Fusername"
```

---

## validate_readme

Lints a markdown file against documentation guidelines. Currently checks for emoji usage; returns a score (0-100, passing is 70+) with line-level issue locations.

**CLI:** `node tools/cli/cybr-demos.js validate-readme`

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `filePath` | string | Yes | Path relative to `demos/` (e.g., `secrets_manager/myapp/README.md`) |

### Response fields

| Field | Description |
|-------|-------------|
| `passed` | Boolean pass/fail (score >= 70) |
| `score` | 0-100. Emojis deduct 5 points each (max -30). |
| `issues` | Array of guideline violations with line numbers and previews |
| `suggestions` | Actionable fix recommendations |

---

## Global contract envelope

All tools wrap responses in:

```json
{
  "status": "ok | partial | error",
  "request_id": "uuid",
  "tool_name": "string",
  "contract_version": "global/v1",
  "duration_ms": 0,
  "result": {},
  "warnings": [],
  "errors": [],
  "meta": {
    "timestamp_utc": "ISO-8601",
    "redactions_applied": 0,
    "next_cursor": null
  }
}
```

Mutating tools (`create_demo`, `create_demo_safe`, `provision_safe`, `provision_workload`) accept optional `idempotency_key` and `dry_run` parameters. Missing idempotency keys on mutating calls produce a warning.

Errors use typed codes: `VALIDATION_FAILED`, `AUTH_FAILED`, `PERMISSION_DENIED`, `RESOURCE_NOT_FOUND`, `RESOURCE_CONFLICT`, `RATE_LIMITED`, `DEPENDENCY_UNAVAILABLE`, `INTERNAL_ERROR`. Each error includes `retryable`, `http_status`, and `remediation` fields.
