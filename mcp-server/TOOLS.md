# MCP Server Tools Documentation

This document provides detailed documentation for all tools available in the CyberArk Demos MCP Server.

## Table of Contents

- [create_demo](#create_demo)
- [create_demo_safe](#create_demo_safe)
- [provision_safe](#provision_safe)
- [provision_workload](#provision_workload)
- [validate_readme](#validate_readme)

---

## create_demo

Creates a new demo with standard scaffolding files including README.md, info.yaml, demo.sh, setup.sh, and setup directory. The demo will be created in the appropriate category directory under `demos/`.

### Parameters

#### Required Parameters

- **`category`** (string, enum)
  - Demo category. Must be one of:
    - `credential_providers` - CyberArk Credential Providers
    - `secrets_manager` - Conjur/Secrets Manager integrations
    - `secrets_hub` - Secrets Hub integrations
    - `utility` - Utility demos and helper tools
  
- **`name`** (string)
  - Name of the demo
  - Will be converted to lowercase with underscores for directory name
  - Example: "AWS Lambda" becomes "aws_lambda"

#### Optional Parameters

- **`displayName`** (string)
  - Display name for the demo (used in README and info.yaml)
  - Defaults to `name` if not provided
  - Example: "AWS Lambda Integration"

- **`categoryLabel`** (string)
  - Custom category label for info.yaml
  - Defaults to `category` if not provided
  - Example: "Secrets Manager"

- **`description`** (string)
  - Description of the demo for README
  - Uses placeholder if not provided

- **`docs`** (string)
  - Documentation URL
  - Defaults to CyberArk docs portal

- **`demoScript`** (string)
  - Name of the demo script file
  - Defaults to "demo.sh"

- **`setupScript`** (string)
  - Name of the setup script file
  - Defaults to "setup.sh"

### Example Usage

#### Basic Example
```
Create a new secrets_manager demo called "jenkins"
```

#### Advanced Example
```
Create a secrets_manager demo called "azure_devops" with:
- Display name: "Azure DevOps"
- Description: "Demonstrates how to integrate CyberArk Secrets Manager with Azure DevOps for secure credential retrieval in CI/CD pipelines"
```

### Output Structure

Creates the following directory structure:

```
demos/{category}/{demo_name}/
├── README.md              # Documentation template
├── info.yaml             # Demo metadata
├── demo.sh               # Main demo script (executable)
├── setup.sh              # Setup script (executable)
└── setup/
    └── configure.sh      # Configuration script (executable)
```

### Response

Returns a JSON object:

```json
{
  "success": true,
  "path": "/full/path/to/demos/category/demo_name",
  "files": [
    "info.yaml",
    "README.md",
    "demo.sh",
    "setup.sh",
    "setup/configure.sh"
  ]
}
```

---

## create_demo_safe

Creates scaffolding for CyberArk Privilege Cloud safe setup. This tool generates a `setup/vault` directory structure with scripts to create and configure a safe using the CyberArk Privilege Cloud REST APIs.

### Purpose

This tool automates the creation of safe setup scripts that:
- Create a new safe in CyberArk Privilege Cloud
- Configure safe permissions and members
- Optionally set up Conjur synchronization
- Optionally create test accounts
- Follow the established patterns from existing demos

### Prerequisites

- An existing demo directory (created with `create_demo`)
- Access to CyberArk Privilege Cloud tenant
- Environment variables configured in `demos/tenant_vars.sh`
- Utility functions available in `demos/utility/ubuntu/`

### Parameters

#### Required Parameters

- **`demoPath`** (string)
  - Path to the demo directory relative to `demos/` base directory
  - Example: `"secrets_manager/azure_devops"`
  - Example: `"secrets_hub/aws_secrets_manager"`

#### Optional Parameters

- **`safeName`** (string)
  - Name of the safe to create in CyberArk Privilege Cloud
  - **Defaults to**: `${LAB_ID}-{demo-name}` where demo name is extracted from the path and normalized (spaces and non-alphanumeric characters replaced with hyphens, converted to lowercase)
  - Example: For demo path `"secrets_manager/azure_devops"`, default would be `${LAB_ID}-azure-devops`
  - Example: For demo path `"secrets_manager/K8s Demo"`, default would be `${LAB_ID}-k8s-demo`
  - You can override by providing explicit value: `"poc-azure-devops"`, `"demo-k8s-secrets"`

- **`addSyncMember`** (boolean)
  - Add "Conjur Sync" user as a read member to the safe
  - Required for Conjur/Secrets Hub synchronization
  - Automatically enabled for `secrets_manager` demos
  - Defaults to `false` for non-`secrets_manager` demos

- **`createAccount`** (boolean)
  - Include account creation in the setup script
  - Creates a test SSH account: `account-ssh-user-1`
  - Defaults to `false`

- **`setupConjur`** (boolean)
  - Include Conjur synchronizer setup in the script
  - Waits for synchronizer to detect the safe
  - Requires `addSyncMember` to be `true`
  - Defaults to `false`

- **`additionalVars`** (string)
  - Additional environment variables to include in `vars.env`
  - Multiline string with shell variable definitions
  - Example: `"JWT_CLAIM_IDENTITY=\"github-user\"\nAPP_ID=\"my-app\""`

### Example Usage

#### Basic Safe Setup (Using Default Safe Name)
```
Create a demo safe for secrets_manager/azure_devops
```
This will use the default safe name: `${LAB_ID}-azure-devops`

#### Basic Safe Setup (Custom Safe Name)
```
Create a demo safe for the azure_devops demo with safe name "poc-azure-devops"
```

#### Advanced Setup with Conjur Sync
```
Create a demo safe for secrets_manager/k8s with:
- Add Conjur Sync member: true
- Setup Conjur: true
- Create account: true
```
This will use default safe name: `${LAB_ID}-k8s`

#### With Custom Variables
```
Create a demo safe for secrets_manager/github_actions with:
- Safe name: "poc-github"
- Additional vars: 'JWT_CLAIM_IDENTITY="INPUT_REQUIRED: github-name"\nAPP_ID="github-actions"'
```

### Output Structure

Creates the following directory structure:

```
demos/{category}/{demo_name}/
└── setup/
    └── vault/
        ├── vars.env            # Environment variables
        └── setup.sh           # Main setup script (executable)
```

### Generated Files

#### vars.env
Contains safe-specific environment variables:
```bash
# CyberArk Vault
SAFE_NAME="${LAB_ID}-azure-devops"

# Add additional environment variables here
```
Note: If you provide a custom `safeName`, that value will be used instead of the default pattern.

#### setup.sh
Main orchestration script that:
1. Sources common environment and utility functions
2. Loads variables from `vars.env`
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
  "path": "/full/path/to/demos/category/demo_name/setup/vault",
  "files": [
    "vars.env",
    "setup.sh"
  ]
}
```

### Dependencies

The generated scripts depend on functions from:

- **`demos/setup_env.sh`** - Loads all utility functions
- **`demos/tenant_vars.sh`** - Tenant configuration
- **`demos/utility/ubuntu/identity_functions.sh`** - Identity token functions
- **`demos/utility/ubuntu/priviledge_functions.sh`** - Safe/account functions
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

Provisions a safe in CyberArk Privilege Cloud and optionally creates accounts. This tool executes the actual API calls using environment variables from `tenant_vars.sh`. **No user input required** - uses system environment variables automatically.

### Purpose

This tool automates the actual provisioning of safes by:
- Authenticating to CyberArk Identity using system credentials
- Creating a new safe via Privilege Cloud REST API
- Adding admin permissions automatically
- Optionally adding Conjur Sync member for synchronization
- Optionally creating test accounts
- Optionally setting up Conjur synchronization

Unlike `create_demo_safe` which generates scripts, this tool **executes the provisioning immediately**.

### Prerequisites

**Required Environment Variables** (set in `demos/tenant_vars.sh`):
```bash
TENANT_ID="your-tenant-id"
TENANT_SUBDOMAIN="your-subdomain"
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-client-secret"
```

**Required System Setup**:
- `CYBR_DEMOS_PATH` environment variable must be set
- Utility functions must be available in `demos/utility/ubuntu/`
- Network access to CyberArk Privilege Cloud

### Parameters

#### Required Parameters

- **`demoPath`** (string)
  - Path to the demo directory relative to `demos/` base directory
  - Example: `"secrets_manager/azure_devops"`
  - Used for context and temporary script execution

- **`safeName`** (string)
  - Name of the safe to create in CyberArk Privilege Cloud
  - Example: `"poc-azure-devops"`
  - Must follow CyberArk safe naming conventions

#### Optional Parameters

- **`addSyncMember`** (boolean)
  - Add "Conjur Sync" user as a read member to the safe
  - Required for Secrets Manager/Secrets Hub integration
  - Defaults to `false`

- **`createAccounts`** (boolean)
  - Create test SSH account (`account-ssh-user-1`) in the safe
  - Account details: username=`ssh-user-1`, address=`196.168.0.1`, platform=`UnixSSH`
  - Defaults to `false`

- **`setupConjur`** (boolean)
  - Setup Conjur synchronization and wait for synchronizer to detect the safe
  - Requires `addSyncMember` to be `true`
  - May take several minutes to complete
  - Defaults to `false`

### Example Usage

#### Basic Safe Creation
```
Provision a safe for secrets_manager/azure_devops with safe name "poc-azure-devops"
```

#### Safe with Sync Member
```
Provision a safe for secrets_manager/k8s with:
- Safe name: "poc-k8s-secrets"
- Add Sync Member: true
```

#### Complete Setup with Accounts and Conjur
```
Provision a safe for secrets_manager/k8s with:
- Safe name: "poc-k8s-demo"
- Add Sync Member: true
- Create Accounts: true
- Setup Conjur: true
```

### Execution Flow

1. **Validates** demo path exists
2. **Creates** temporary provisioning script in `demo/setup/`
3. **Sources** environment variables from `tenant_vars.sh`
4. **Authenticates** to CyberArk Identity
5. **Creates** the safe via API
6. **Adds** admin role permissions
7. **Optionally adds** Conjur Sync member
8. **Optionally creates** test accounts
9. **Optionally waits** for Conjur synchronization
10. **Cleans up** temporary script
11. **Returns** execution results

### Response

Returns a JSON object with execution details:

```json
{
  "success": true,
  "safeName": "poc-azure-devops",
  "demoPath": "secrets_manager/azure_devops",
  "output": "Full command output showing all steps...",
  "warnings": "Any warnings or stderr output (optional)"
}
```

### Output Example

```
========================================
Provisioning Safe: poc-azure-devops
========================================

Authenticating to Identity...
✓ Authentication successful

Creating safe: poc-azure-devops...
✓ Safe created

Adding admin role...
✓ Admin role added

Adding Conjur Sync member...
✓ Conjur Sync member added

Creating test account...
✓ Test account created

========================================
Safe provisioning completed successfully!
========================================

Safe Name: poc-azure-devops
Demo Path: secrets_manager/azure_devops
```

### API Calls Made

The tool executes these CyberArk API functions:

1. **`get_identity_token()`**
   - Endpoint: `https://<subdomain>.privilegecloud.cyberark.cloud/oauth2/token`
   - Gets OAuth token for API access

2. **`create_safe()`**
   - Endpoint: `POST /PasswordVault/API/Safes`
   - Creates new safe with specified name

3. **`add_safe_admin_role()`**
   - Endpoint: `POST /PasswordVault/API/Safes/{safeName}/Members`
   - Adds "Privilege Cloud Administrators" with full permissions

4. **`add_safe_read_member()`** (if `addSyncMember=true`)
   - Endpoint: `POST /PasswordVault/API/Safes/{safeName}/Members`
   - Adds "Conjur Sync" user with read permissions

5. **`create_account_ssh_user_1()`** (if `createAccounts=true`)
   - Endpoint: `POST /PasswordVault/API/Accounts`
   - Creates test SSH account in the safe

6. **`get_conjur_token()`** (if `setupConjur=true`)
   - Authenticates to Conjur

7. **`wait_for_synchronizer()`** (if `setupConjur=true`)
   - Polls until synchronizer detects the safe

### Common Use Cases

#### 1. Quick Safe for Testing
```
demoPath: "secrets_manager/test"
safeName: "poc-test-safe"
```

#### 2. Secrets Manager Integration
```
demoPath: "secrets_manager/k8s"
safeName: "poc-k8s-secrets"
addSyncMember: true
createAccounts: true
setupConjur: true
```

#### 3. API Demo with Test Accounts
```
demoPath: "secrets_manager/api_demo"
safeName: "poc-api-accounts"
createAccounts: true
```

### Error Handling

Common errors and solutions:

#### Authentication Failed
```
ERROR: Failed to get identity token
```
**Solution**: Check environment variables in `tenant_vars.sh`

#### Safe Already Exists
```
Failed to provision safe: Safe already exists
```
**Solution**: Use a different safe name or delete the existing safe

#### Network/API Errors
```
Failed to provision safe: Connection timeout
```
**Solution**: Check network connectivity and API endpoint accessibility

#### Missing Environment Variables
```
TENANT_ID: unbound variable
```
**Solution**: Ensure `CYBR_DEMOS_PATH` is set and `tenant_vars.sh` exists

### Security Considerations

- **Credentials**: Uses OAuth client credentials (not user passwords)
- **Token Storage**: Tokens are temporary and not persisted
- **Script Cleanup**: Temporary scripts are automatically deleted
- **Audit Trail**: All API calls are logged in Privilege Cloud audit

### Comparison: provision_safe vs create_demo_safe

| Feature | provision_safe | create_demo_safe |
|---------|---------------|------------------|
| **Action** | Executes API calls | Generates scripts |
| **When to Use** | Ready to provision now | Need scripts for later |
| **Requirements** | Valid credentials | None |
| **Output** | Created safe in cloud | Shell scripts on disk |
| **User Input** | None (uses env vars) | Requires manual execution |
| **Immediate Result** | Yes | No |

### Best Practices

1. **Test credentials first**: Verify `tenant_vars.sh` is correctly configured
2. **Use descriptive names**: Include "poc-" prefix and demo identifier
3. **Enable sync for SM**: Always use `addSyncMember: true` for Secrets Manager demos
4. **Create accounts when needed**: Use `createAccounts: true` for demos that need test data
5. **Monitor output**: Check the output for any warnings or errors
6. **Cleanup after demos**: Delete test safes when no longer needed

### Troubleshooting

#### Demo Path Not Found
```bash
# Verify demo exists
ls -la demos/secrets_manager/azure_devops
```

#### Environment Not Sourced
```bash
# Check if CYBR_DEMOS_PATH is set
echo $CYBR_DEMOS_PATH

# Set if missing
export CYBR_DEMOS_PATH="/path/to/cybr-demos"
```

#### Permission Errors
```bash
# Ensure setup directory exists
mkdir -p demos/secrets_manager/azure_devops/setup
chmod 755 demos/secrets_manager/azure_devops/setup
```

#### API Rate Limiting
If you see rate limiting errors, wait a few minutes between provision attempts.

---

## provision_workload

Provisions a Secrets Manager workload with API key authentication and grants it access to a specified safe. This tool creates the workload policy in Conjur, rotates the API key, and securely saves the credentials. **No user input required** - uses system environment variables automatically.

### Purpose

This tool automates the creation of Secrets Manager workloads by:
- Creating a host identity in Conjur with API key authentication enabled
- Granting the workload access to consume secrets from a specified safe
- Rotating the API key to get a fresh credential
- Saving the workload credentials to a secure file
- Providing usage examples for authentication and secret retrieval

This tool complements `provision_safe` - first create the safe, then create workloads to access it.

### Prerequisites

**Required Environment Variables** (set in `demos/tenant_vars.sh`):
```bash
TENANT_ID="your-tenant-id"
TENANT_SUBDOMAIN="your-subdomain"
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-client-secret"
```

**Required System Setup**:
- `CYBR_DEMOS_PATH` environment variable must be set
- Utility functions must be available in `demos/utility/ubuntu/`
- The target safe must already exist (create with `provision_safe` first)
- Network access to CyberArk Secrets Manager

### Parameters

#### Required Parameters

- **`demoPath`** (string)
  - Path to the demo directory relative to `demos/` base directory
  - Example: `"secrets_manager/azure_devops"`
  - Used for context and credential file storage

- **`safeName`** (string)
  - Name of the safe to grant access to
  - Example: `"poc-azure-devops"`
  - **Must already exist** - create it first with `provision_safe`

- **`workloadName`** (string)
  - Name/identifier for the workload
  - Will be created as `data/workloads/{workloadName}`
  - Example: `"azure-devops-pipeline"`, `"jenkins-job-1"`, `"app-server-prod"`
  - Use descriptive names that identify the consuming application/service

### Example Usage

#### Basic Workload Creation
```
Provision a workload for secrets_manager/azure_devops with:
- Safe name: "poc-azure-devops"
- Workload name: "azure-devops-pipeline"
```

#### Multiple Workloads for Same Safe
```
Provision a workload for secrets_manager/jenkins with:
- Safe name: "poc-jenkins"
- Workload name: "jenkins-prod-job"

Provision a workload for secrets_manager/jenkins with:
- Safe name: "poc-jenkins"
- Workload name: "jenkins-dev-job"
```

#### Application Server Workload
```
Provision a workload for secrets_manager/app_demo with:
- Safe name: "poc-app-secrets"
- Workload name: "webapp-server-01"
```

### Execution Flow

1. **Validates** demo path exists
2. **Creates** temporary provisioning script
3. **Authenticates** to CyberArk Identity
4. **Authenticates** to Conjur (Secrets Manager)
5. **Creates** workload policy with API key authentication
6. **Grants** workload access to the specified safe
7. **Rotates** API key to get fresh credentials
8. **Saves** credentials to secure file (mode 600)
9. **Cleans up** temporary script
10. **Returns** workload details and credentials location

### Response

Returns a JSON object with provisioning details:

```json
{
  "success": true,
  "workloadName": "azure-devops-pipeline",
  "safeName": "poc-azure-devops",
  "demoPath": "secrets_manager/azure_devops",
  "output": "Full command output showing all steps...",
  "warnings": "Any warnings or stderr output (optional)"
}
```

### Output Example

```
========================================
Provisioning Workload: azure-devops-pipeline
========================================

Authenticating to Identity...
✓ Authentication successful

Authenticating to Conjur...
✓ Conjur authentication successful

Creating workload policy...
✓ Workload policy created

Rotating API key for workload...
✓ API key rotated

Saving credentials to file...
✓ Credentials saved to: demos/secrets_manager/azure_devops/setup/.workload_credentials_azure-devops-pipeline.txt

========================================
Workload provisioning completed successfully!
========================================

Workload Name: azure-devops-pipeline
Login: host/data/workloads/azure-devops-pipeline
Safe Access: poc-azure-devops
Credentials File: demos/secrets_manager/azure_devops/setup/.workload_credentials_azure-devops-pipeline.txt

IMPORTANT: Store the API key securely!
```

### Generated Credentials File

The tool creates a secure credentials file at:
```
demos/{category}/{demo}/setup/.workload_credentials_{workloadName}.txt
```

**File permissions:** `600` (owner read/write only)

**File contents:**
```
========================================
Workload Credentials
========================================
Workload Name: azure-devops-pipeline
Login: host/data/workloads/azure-devops-pipeline
API Key: 3x4mpl3k3y1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s

Safe Access: poc-azure-devops
Conjur URL: https://subdomain.secretsmgr.cyberark.cloud

========================================
Usage Example:
========================================
# Authenticate
curl -d "3x4mpl3k3y1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s" \
  https://subdomain.secretsmgr.cyberark.cloud/api/authn/conjur/host%2Fdata%2Fworkloads%2Fazure-devops-pipeline/authenticate

# Retrieve secret
curl -H "Authorization: Token token=\"<token>\"" \
  https://subdomain.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2Fpoc-azure-devops%2F<account-id>%2Fusername
```

### Workload Policy Created

The tool creates this Conjur policy:

```yaml
# Workload identity with API key authentication
- !host
  id: workloads/{workloadName}
  annotations:
    authn/api-key: true

# Grant access to the safe
- !grant
  roles:
    - !group vault/{safeName}/delegation/consumers
  members:
    - !host workloads/{workloadName}
```

### API Calls Made

The tool executes these API calls:

1. **`get_identity_token()`**
   - Authenticates to CyberArk Identity
   - Gets OAuth token for API access

2. **`get_conjur_token()`**
   - Authenticates to Conjur using Identity token
   - Gets Conjur API token

3. **`apply_conjur_policy()`**
   - Endpoint: `POST /api/policies/conjur/policy/data`
   - Creates the workload host and grants safe access

4. **`PUT /api/authn/conjur/api_key?role=host:{workloadId}`**
   - Rotates the workload's API key
   - Returns new API key for authentication

### Common Use Cases

#### 1. CI/CD Pipeline Access
```
demoPath: "secrets_manager/azure_devops"
safeName: "poc-azure-devops"
workloadName: "build-pipeline-prod"
```

#### 2. Multiple Jenkins Jobs
```
# Job 1
demoPath: "secrets_manager/jenkins"
safeName: "poc-jenkins"
workloadName: "jenkins-deploy-job"

# Job 2
demoPath: "secrets_manager/jenkins"
safeName: "poc-jenkins"
workloadName: "jenkins-test-job"
```

#### 3. Application Servers
```
demoPath: "secrets_manager/webapp"
safeName: "poc-webapp-secrets"
workloadName: "webapp-server-01"
```

#### 4. Microservices
```
# Service 1
demoPath: "secrets_manager/microservices"
safeName: "poc-microservices"
workloadName: "auth-service"

# Service 2
demoPath: "secrets_manager/microservices"
safeName: "poc-microservices"
workloadName: "api-gateway"
```

### Error Handling

Common errors and solutions:

#### Safe Does Not Exist
```
ERROR: Failed to create workload policy
```
**Solution**: Create the safe first with `provision_safe`

#### Authentication Failed
```
ERROR: Failed to get identity token
ERROR: Failed to get Conjur token
```
**Solution**: Check credentials in `tenant_vars.sh` and network connectivity

#### Demo Path Not Found
```
Demo path does not exist: secrets_manager/myapp
```
**Solution**: Create the demo first with `create_demo`

#### Workload Already Exists
```
ERROR: Policy already exists
```
**Solution**: Use a different workload name or delete the existing one

### Security Considerations

- **API Key Storage**: Credentials file has `600` permissions (owner only)
- **Secure Location**: File stored in `setup/` directory, not in public paths
- **File Naming**: Prefixed with `.` to hide from normal directory listings
- **No Logging**: API key not logged to stdout, only saved to secure file
- **Rotation**: Fresh API key generated during provisioning
- **Access Control**: Workload only gets access to specified safe

### Using the Workload Credentials

#### Step 1: Read the Credentials File
```bash
cat demos/secrets_manager/azure_devops/setup/.workload_credentials_azure-devops-pipeline.txt
```

#### Step 2: Authenticate to Secrets Manager
```bash
WORKLOAD_LOGIN="host/data/workloads/azure-devops-pipeline"
API_KEY="<your-api-key-from-file>"
SUBDOMAIN="your-subdomain"

# Get access token
TOKEN=$(curl -d "$API_KEY" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn/conjur/${WORKLOAD_LOGIN}/authenticate" \
  | base64 | tr -d '\r\n')
```

#### Step 3: Retrieve Secrets
```bash
# Get a secret value
curl -H "Authorization: Token token=\"$TOKEN\"" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2Fpoc-azure-devops%2Faccount-ssh-user-1%2Fusername"
```

### Comparison: provision_workload vs Manual Setup

| Task | Manual | provision_workload |
|------|--------|-------------------|
| **Create policy file** | Write YAML manually | Automated |
| **Apply policy** | Run CLI command | Automated |
| **Rotate API key** | Run API call manually | Automated |
| **Save credentials** | Copy/paste to file | Automated |
| **Set permissions** | `chmod` manually | Automated (600) |
| **URL encoding** | Manual encoding | Automated |
| **Time required** | 5-10 minutes | 10-15 seconds |
| **Error prone** | Yes | No |

### Best Practices

1. **Use descriptive workload names**: Include app name and environment
   - ✅ `jenkins-prod-deploy-job`
   - ✅ `webapp-server-prod-01`
   - ❌ `workload1`, `test`

2. **Create safe first**: Always use `provision_safe` before `provision_workload`

3. **One workload per consumer**: Don't share API keys between applications

4. **Secure credential files**: 
   - Keep in `setup/` directory
   - Add to `.gitignore`
   - Delete after distributing to application

5. **Rotate API keys regularly**: Use the rotation API for production workloads

6. **Document workload purpose**: Include in demo README what each workload is for

### Integration with Other Tools

#### Complete Workflow Example

```
# Step 1: Create demo structure
Create a secrets_manager demo called "my_app"

# Step 2: Provision the safe
Provision a safe for secrets_manager/my_app with:
- Safe name: "poc-my-app"
- Add sync member: true
- Create accounts: true

# Step 3: Provision workload(s)
Provision a workload for secrets_manager/my_app with:
- Safe name: "poc-my-app"
- Workload name: "my-app-prod"

Provision a workload for secrets_manager/my_app with:
- Safe name: "poc-my-app"
- Workload name: "my-app-dev"

# Step 4: Use credentials in your application
# Read the .workload_credentials_*.txt files
```

### Troubleshooting

#### Credentials File Not Found
```bash
# List credential files
ls -la demos/secrets_manager/azure_devops/setup/.workload_credentials_*
```

#### API Key Not Working
```bash
# Test authentication
curl -v -d "$API_KEY" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn/conjur/host%2Fdata%2Fworkloads%2F$WORKLOAD_NAME/authenticate"
```

#### Cannot Access Secrets
Verify the workload has access:
1. Check safe name matches
2. Verify safe has "Conjur Sync" member
3. Check Conjur synchronization completed

#### Permission Denied on Credentials File
```bash
chmod 600 demos/secrets_manager/azure_devops/setup/.workload_credentials_*.txt
```

### Cleanup

To remove a workload (manual process):
1. Delete the credentials file
2. Update Conjur policy to remove the host
3. Revoke safe access

*Note: Automated workload deletion will be added in a future release*

---

## validate_readme

Validates README and markdown files against documentation guidelines. Checks for common issues like emojis, formatting problems, and documentation standards. Returns validation results with suggestions for improvements.

### Purpose

This tool helps maintain consistent, professional documentation by:
- Enforcing documentation style guidelines
- Detecting emojis and suggesting text alternatives
- Providing a quality score for documentation
- Offering specific suggestions for improvements
- Ensuring professional, enterprise-ready documentation

This tool is particularly useful for ensuring demos have consistent, professional documentation that meets enterprise standards.

### Prerequisites

- File must exist in the demos directory structure
- File should be a markdown (.md) file

### Parameters

#### Required Parameters

- **`filePath`** (string)
  - Path to the markdown file relative to `demos/` base directory
  - Example: `"secrets_manager/azure_devops/README.md"`
  - Example: `"credential_providers/ccp/README.md"`
  - Can be any markdown file in the demos directory

### Guidelines Checked

#### 1. No Emojis

**Guideline:** Documentation should not contain emojis.

**Rationale:**
- Enterprise documentation should be professional and text-based
- Emojis may not render consistently across all platforms
- Some email clients and documentation systems don't support emojis
- Text descriptions are more accessible and searchable

**Examples:**

❌ **Bad:**
```markdown
## 🚀 Quick Start
✅ Feature enabled
❌ Not supported
```

✅ **Good:**
```markdown
## Quick Start
- Feature enabled
- Not supported
```

**Severity:** Warning  
**Impact on Score:** -5 points per emoji occurrence (max -30)

### Example Usage

#### Basic Validation
```
Validate the readme file at secrets_manager/azure_devops/README.md
```

#### Check Multiple Files
```
Validate secrets_manager/jenkins/README.md
Validate credential_providers/ccp/README.md
Validate secrets_hub/aws/README.md
```

#### Validate Before Commit
```
Validate the readme at secrets_manager/myapp/README.md
```

### Response

Returns a JSON object with validation results:

```json
{
  "success": true,
  "filePath": "secrets_manager/azure_devops/README.md",
  "passed": false,
  "score": 85,
  "issues": [
    {
      "guideline": "No Emojis",
      "severity": "warning",
      "count": 3,
      "message": "Found 3 line(s) containing emojis",
      "locations": [
        {
          "line": 5,
          "preview": "## 🚀 Quick Start",
          "emojis": "🚀"
        },
        {
          "line": 23,
          "preview": "✅ Feature enabled",
          "emojis": "✅"
        },
        {
          "line": 24,
          "preview": "❌ Not supported",
          "emojis": "❌"
        }
      ]
    }
  ],
  "suggestions": [
    "Remove emojis from documentation. Use descriptive text instead."
  ],
  "summary": {
    "totalIssues": 1,
    "guidelinesChecked": 1,
    "guidelinesPassed": 0
  }
}
```

### Output Example

#### Passed Validation

```
Validation Results
==================
File: secrets_manager/myapp/README.md
Status: PASSED ✓
Score: 100/100

Summary:
- Total Issues: 0
- Guidelines Checked: 1
- Guidelines Passed: 1

All guidelines passed!
```

#### Failed Validation

```
Validation Results
==================
File: secrets_manager/azure_devops/README.md
Status: FAILED ✗
Score: 85/100

Issues Found:
-------------
1. No Emojis [WARNING]
   Found 3 line(s) containing emojis
   
   Locations:
   - Line 5: ## 🚀 Quick Start
     Emojis: 🚀
   
   - Line 23: ✅ Feature enabled
     Emojis: ✅
   
   - Line 24: ❌ Not supported
     Emojis: ❌

Suggestions:
------------
- Remove emojis from documentation. Use descriptive text instead.

Summary:
- Total Issues: 1
- Guidelines Checked: 1
- Guidelines Passed: 0
```

### Scoring System

**Score Range:** 0-100

**Passing Score:** 70+

**Deductions:**
- Emojis: -5 points per occurrence (max -30)

**Score Interpretation:**
- **90-100:** Excellent - Professional documentation
- **70-89:** Good - Minor improvements needed
- **50-69:** Fair - Several issues to address
- **0-49:** Poor - Major improvements required

### Common Use Cases

#### 1. Pre-Commit Validation
Before committing documentation:
```
Validate secrets_manager/myapp/README.md
```

#### 2. Demo Review
Before sharing a demo:
```
Validate secrets_manager/demo_name/README.md
```

#### 3. Bulk Validation
Check multiple files:
```
Validate secrets_manager/jenkins/README.md
Validate secrets_manager/k8s/README.md
Validate secrets_manager/azure_devops/README.md
```

#### 4. Documentation Audit
Review existing documentation:
```
Validate credential_providers/ccp/README.md
```

### Fixing Issues

#### Removing Emojis

**Before:**
```markdown
## 🚀 Quick Start

Follow these steps:
1. ✅ Install dependencies
2. ⚙️ Configure settings
3. 🎉 Run the demo

### Features
- ✅ Secure authentication
- ✅ Automatic rotation
- ❌ Manual management
```

**After:**
```markdown
## Quick Start

Follow these steps:
1. Install dependencies
2. Configure settings
3. Run the demo

### Features
- Secure authentication
- Automatic rotation
- Manual management not supported
```

**Tips for Replacing Emojis:**
- 🚀 Quick Start → Quick Start
- ✅ Done/Yes/Enabled → "enabled", "yes", "supported"
- ❌ Not supported → "not supported", "disabled"
- ⚠️ Warning → "Warning:", "Note:"
- 📝 Note → "Note:", "Important:"
- 🔧 Configuration → Configuration
- 🎯 Goal → Goal, Objective
- 💡 Tip → "Tip:", "Hint:"
- 🐛 Bug → Bug, Issue

### Integration with Workflow

#### Step 1: Create Demo
```
Create a secrets_manager demo called "myapp"
```

#### Step 2: Edit README
```bash
nano demos/secrets_manager/myapp/README.md
# Add your documentation
```

#### Step 3: Validate
```
Validate secrets_manager/myapp/README.md
```

#### Step 4: Fix Issues
```bash
# Remove emojis and other issues
nano demos/secrets_manager/myapp/README.md
```

#### Step 5: Re-validate
```
Validate secrets_manager/myapp/README.md
```

#### Step 6: Commit
```bash
git add demos/secrets_manager/myapp/README.md
git commit -m "Add myapp demo documentation"
```

### Best Practices

1. **Validate Early**: Check documentation as you write it
2. **Aim for 100**: Try to achieve a perfect score
3. **Use Text**: Replace emojis with descriptive text
4. **Be Professional**: Enterprise documentation should be formal
5. **Consistent Style**: Follow the same patterns across all READMEs
6. **Descriptive Headers**: Use clear, emoji-free section headers
7. **Validate Before Commit**: Always validate before committing

### Error Handling

#### File Not Found
```
Error: File does not exist: secrets_manager/nonexistent/README.md
```

**Solution:** Check the file path and ensure it's relative to `demos/`

#### Invalid Path
```
Error: File does not exist: /absolute/path/README.md
```

**Solution:** Use relative path from `demos/` directory

### Future Guidelines

Planned additions:

- **No Excessive Exclamation Marks**: Limit to one per sentence
- **Consistent Heading Levels**: No skipped levels (e.g., # to ###)
- **Code Block Language Tags**: All code blocks should specify language
- **Link Validation**: Check for broken links
- **Spelling Check**: Basic spelling validation
- **Line Length**: Recommend max line length
- **Table Formatting**: Consistent table structure
- **List Formatting**: Consistent bullet/number formatting
- **Copyright/License**: Check for required notices
- **Minimum Sections**: Ensure required sections exist

### Comparison: Before vs After Validation

| Aspect | Before | After |
|--------|--------|-------|
| **Emojis** | 15 emojis | 0 emojis |
| **Professionalism** | Casual | Professional |
| **Score** | 25/100 | 100/100 |
| **Enterprise Ready** | No | Yes |
| **Accessibility** | Limited | Full |

### Troubleshooting

#### Too Many Emojis
**Problem:** Score dropped significantly

**Solution:**
1. Review the locations list
2. Replace each emoji with descriptive text
3. Re-validate
4. Repeat until score > 70

#### False Positives
**Problem:** Tool detected emoji that isn't visible

**Solution:**
- Some characters may appear as emojis in certain encodings
- Check the specific line number
- Look for special Unicode characters
- Replace with standard ASCII text

#### Score Still Low After Fixes
**Problem:** Fixed emojis but score not improving

**Solution:**
- Ensure all emojis are removed (check locations list)
- Some emojis may be in code blocks or comments
- Re-validate after each fix
- Check for hidden Unicode characters

### Examples by Category

#### Demo README
```
Validate secrets_manager/jenkins/README.md
```

#### Setup Documentation
```
Validate secrets_manager/k8s/setup/README.md
```

#### Category Overview
```
Validate secrets_manager/README.md
```

---

## Error Handling

All tools return consistent error responses:

```json
{
  "success": false,
  "error": "Error message description"
}
```

Common errors:

- **Demo already exists**: Delete or rename existing demo
- **Invalid category**: Use one of the four valid categories
- **Demo path not found**: Create demo first with `create_demo`
- **Permission denied**: Check file/directory permissions

---

## Future Tools

Potential tools to add:

- **`delete_demo`** - Remove a demo and its contents
- **`delete_safe`** - Delete a safe from Privilege Cloud
- **`delete_workload`** - Remove a workload from Secrets Manager
- **`list_workloads`** - List all workloads for a demo/safe
- **`rotate_workload_key`** - Rotate a workload's API key
- **`create_app_id`** - Generate Application ID setup scripts
- **`provision_app_id`** - Create Application ID via API
- **`create_conjur_policy`** - Generate Conjur policy files
- **`create_k8s_manifests`** - Generate Kubernetes deployment manifests
- **`create_cleanup_script`** - Generate cleanup/teardown scripts
- **`list_safes`** - List all safes in tenant
- **`get_safe_info`** - Get details about a specific safe
- **`provision_jwt_auth`** - Create JWT authenticator for workloads
- **`validate_documentation`** - Enhanced validation with more guidelines
- **`fix_readme`** - Auto-fix common documentation issues

---

## Contributing

To add a new tool:

1. Define the tool in `ListToolsRequestSchema` handler
2. Implement the tool logic function
3. Add handler in `CallToolRequestSchema`
4. Document the tool in this file
5. Add examples and test cases
6. Update main README.md with summary

---

**Last Updated**: February 2024
**Version**: 1.3.0