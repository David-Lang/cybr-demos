# MCP Server Tools Documentation

This document provides detailed documentation for all tools available in the CyberArk Demos MCP Server.

## Table of Contents

- [create_demo](#create_demo)
- [create_demo_safe](#create_demo_safe)

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

- **`safeName`** (string)
  - Name of the safe to create in CyberArk Privilege Cloud
  - Example: `"poc-azure-devops"`
  - Example: `"demo-k8s-secrets"`

#### Optional Parameters

- **`addSyncMember`** (boolean)
  - Add "Conjur Sync" user as a read member to the safe
  - Required for Conjur/Secrets Hub synchronization
  - Defaults to `false`

- **`createAccount`** (boolean)
  - Include account creation in the setup script
  - Creates a test SSH account: `account-ssh-user-1`
  - Defaults to `false`

- **`setupConjur`** (boolean)
  - Include Conjur synchronizer setup in the script
  - Waits for synchronizer to detect the safe
  - Requires `addSyncMember` to be `true`
  - Defaults to `false`

- **`createAccountsScript`** (boolean)
  - Create a separate `create_accounts.sh` script
  - Useful for demos that need standalone account creation
  - Defaults to `false`

- **`additionalVars`** (string)
  - Additional environment variables to include in `vars.env`
  - Multiline string with shell variable definitions
  - Example: `"JWT_CLAIM_IDENTITY=\"github-user\"\nAPP_ID=\"my-app\""`

### Example Usage

#### Basic Safe Setup
```
Create a demo safe for the azure_devops demo with safe name "poc-azure-devops"
```

#### Advanced Setup with Conjur Sync
```
Create a demo safe for secrets_manager/k8s with:
- Safe name: "poc-k8s-secrets"
- Add Conjur Sync member: true
- Setup Conjur: true
- Create account: true
- Create accounts script: true
```

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
        ├── setup.sh           # Main setup script (executable)
        ├── create_safe.sh     # Safe creation script (executable)
        └── create_accounts.sh # Account creation script (executable, optional)
```

### Generated Files

#### vars.env
Contains safe-specific environment variables:
```bash
# CyberArk Vault
SAFE_NAME="poc-azure-devops"

# Add additional environment variables here
```

#### setup.sh
Main orchestration script that:
1. Sources common environment and utility functions
2. Gets Identity authentication token
3. Creates the safe
4. Adds admin role permissions
5. Optionally adds Conjur Sync member
6. Optionally creates test accounts
7. Optionally sets up Conjur synchronization

#### create_safe.sh
Standalone script to create just the safe and basic permissions.

#### create_accounts.sh (optional)
Standalone script to create test accounts in the safe.

### Response

Returns a JSON object:

```json
{
  "success": true,
  "path": "/full/path/to/demos/category/demo_name/setup/vault",
  "files": [
    "vars.env",
    "setup.sh",
    "create_safe.sh",
    "create_accounts.sh"
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
```

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

#### 1. Simple Safe for API Testing
```
demoPath: "secrets_manager/api_test"
safeName: "poc-api-test"
```

#### 2. Secrets Manager with Conjur Sync
```
demoPath: "secrets_manager/k8s"
safeName: "poc-k8s-secrets"
addSyncMember: true
setupConjur: true
createAccount: true
```

#### 3. Credential Provider Demo
```
demoPath: "credential_providers/ccp"
safeName: "poc-ccp-accounts"
createAccount: true
createAccountsScript: true
```

#### 4. GitHub Actions with JWT
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

1. **Use descriptive safe names**: Include demo name and "poc" prefix
2. **Enable Conjur Sync** when using Secrets Manager/Secrets Hub
3. **Create test accounts** for demos that need them
4. **Document custom variables** in the demo's README
5. **Test safe creation** before running full demo setup

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
- **`create_app_id`** - Generate Application ID setup scripts
- **`create_conjur_policy`** - Generate Conjur policy files
- **`create_k8s_manifests`** - Generate Kubernetes deployment manifests
- **`create_cleanup_script`** - Generate cleanup/teardown scripts

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
**Version**: 1.0.0